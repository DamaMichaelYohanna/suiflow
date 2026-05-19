import unittest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from main import app
from database import Base, get_db
import models
import schemas
import time
import os

# Use an in-memory or dedicated SQLite database for testing
SQLALCHEMY_DATABASE_URL = "sqlite:///./test_app.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    try:
        db = TestingSessionLocal()
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

class TestSuiFlowBackend(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=engine)
        cls.client = TestClient(app)
        cls.token = None
        cls.alice_private_key = None

    @classmethod
    def tearDownClass(cls):
        Base.metadata.drop_all(bind=engine)
        if os.path.exists("./test_app.db"):
            try:
                os.remove("./test_app.db")
            except:
                pass

    def test_1_register_user(self):
        response = self.client.post(
            "/api/auth/register",
            json={
                "phone_number": "+1234567890",
                "username": "alice",
                "password": "securepassword",
                "full_name": "Alice Smith"
            }
        )
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertEqual(data["user"]["phone_number"], "+1234567890")
        self.assertEqual(data["user"]["username"], "alice")
        self.assertIsNotNone(data["user"]["wallet"])
        self.assertTrue(len(data["user"]["vaults"]) > 0)
        
        # Save Alice's private key for signing in pipeline test by querying test db directly
        db = TestingSessionLocal()
        try:
            db_wallet = db.query(models.Wallet).join(models.User).filter(models.User.username == "alice").first()
            TestSuiFlowBackend.alice_private_key = db_wallet.encrypted_keypair
        finally:
            db.close()

        # Fund Alice's wallet with SUI so she can perform transactions
        from services.sui_client import client
        if client:
            from pysui.sui.sui_txn import SyncTransaction
            from pysui.sui.sui_types.address import SuiAddress
            alice_address = data["user"]["wallet"]["address"]
            txn = SyncTransaction(client=client)
            split_coin = txn.split_coin(coin=txn.gas, amounts=[50000000]) # 0.05 SUI
            txn.transfer_objects(transfers=[split_coin], recipient=SuiAddress(alice_address))
            res = txn.execute()
            if res.is_err():
                print(f"Warning: Failed to fund Alice: {res.result_string}")
            else:
                print(f"Successfully funded Alice {alice_address} with 0.05 SUI. Digest: {res.result_data.digest}")
                time.sleep(3.0) # Wait for network consensus

        # Register receiver
        response2 = self.client.post(
            "/api/auth/register",
            json={
                "phone_number": "+0987654321",
                "username": "bob",
                "password": "securepassword",
                "full_name": "Bob Jones"
            }
        )
        self.assertEqual(response2.status_code, 200, response2.text)

    def test_2_login_user(self):
        response = self.client.post(
            "/api/auth/login",
            data={
                "username": "+1234567890",
                "password": "securepassword"
            }
        )
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertIn("access_token", data["token"])
        TestSuiFlowBackend.token = data["token"]["access_token"]

    def test_3_lookup_user(self):
        response = self.client.get("/api/auth/lookup?query=bob")
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["phone_number"], "+0987654321")

    def test_4_create_vault(self):
        headers = {"Authorization": f"Bearer {TestSuiFlowBackend.token}"}
        response = self.client.post(
            "/api/vaults/",
            json={"name": "Travel Fund"},
            headers=headers
        )
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertEqual(data["name"], "Travel Fund")
        self.assertTrue(data["object_id"].startswith("vault_"))

        # List vaults
        response_list = self.client.get("/api/vaults/", headers=headers)
        self.assertEqual(response_list.status_code, 200, response_list.text)
        self.assertTrue(len(response_list.json()) >= 3) # Savings, Investment, Travel Fund

    def test_5_send_payment(self):
        headers = {"Authorization": f"Bearer {TestSuiFlowBackend.token}"}
        response = self.client.post(
            "/api/payments/send",
            json={
                "receiver_phone": "+0987654321",
                "amount": 0.01,
                "programmable_split": None
            },
            headers=headers
        )
        self.assertEqual(response.status_code, 200, response.text)
        data = response.json()
        self.assertEqual(data["status"], "PENDING")
        self.assertEqual(data["amount"], 0.01)

        # Wait briefly for background task to complete
        time.sleep(4.0)

    def test_6_sync_offline(self):
        headers = {"Authorization": f"Bearer {TestSuiFlowBackend.token}"}
        response = self.client.post(
            "/api/sync/offline",
            json={
                "transactions": [
                    {
                        "receiver_phone": "+0987654321",
                        "amount": 0.01,
                        "is_offline_queue": True,
                        "programmable_split": None
                    }
                ]
            },
            headers=headers
        )
        self.assertEqual(response.status_code, 202, response.text)
        self.assertIn("Successfully queued", response.json()["message"])
        time.sleep(4.0)

    def test_7_sponsored_transaction_pipeline(self):
        # 1. Create Transaction Intent
        response_intent = self.client.post(
            "/api/tx/intent",
            json={
                "sender_phone": "alice",
                "receiver_phone": "bob",
                "amount": 0.01,
                "programmable_split": None
            }
        )
        self.assertEqual(response_intent.status_code, 200, response_intent.text)
        intent_data = response_intent.json()
        intent_id = intent_data["intent_id"]
        self.assertEqual(intent_data["amount"], 0.01)
        self.assertEqual(intent_data["status"], "INTENT_CREATED")

        # 2. Build Sponsored Transaction
        response_build = self.client.post(
            "/api/tx/build",
            json={"intent_id": intent_id}
        )
        self.assertEqual(response_build.status_code, 200, response_build.text)
        build_data = response_build.json()
        self.assertIsNotNone(build_data["tx_bytes"])
        self.assertEqual(build_data["intent_id"], intent_id)

        # 3. Sponsor Transaction
        response_sponsor = self.client.post(
            "/api/tx/sponsor",
            json={"intent_id": intent_id}
        )
        self.assertEqual(response_sponsor.status_code, 200, response_sponsor.text)
        sponsor_data = response_sponsor.json()
        self.assertIsNotNone(sponsor_data["sponsor_signature"])
        self.assertEqual(sponsor_data["tx_bytes"], build_data["tx_bytes"])

        # 4. Submit Transaction (Client signs and posts)
        from pysui.sui.sui_crypto import SuiKeyPair
        from services.kms_vault import decrypt_private_key
        decrypted_pk = decrypt_private_key(TestSuiFlowBackend.alice_private_key)
        kp = SuiKeyPair.from_b64(decrypted_pk)
        user_sig = kp.new_sign_secure(build_data["tx_bytes"]).value

        response_submit = self.client.post(
            "/api/tx/submit",
            json={
                "intent_id": intent_id,
                "user_signature": user_sig
            }
        )
        self.assertEqual(response_submit.status_code, 200, response_submit.text)
        submit_data = response_submit.json()
        self.assertEqual(submit_data["intent_id"], intent_id)
        self.assertEqual(submit_data["status"], "SUCCESS")
        self.assertIsNotNone(submit_data["sui_digest"])
        self.assertFalse(submit_data["sui_digest"].startswith("mock_digest_"))

        # 5. Idempotency Check (Submit again)
        response_submit_dup = self.client.post(
            "/api/tx/submit",
            json={
                "intent_id": intent_id,
                "user_signature": user_sig
            }
        )
        self.assertEqual(response_submit_dup.status_code, 200, response_submit_dup.text)
        submit_dup_data = response_submit_dup.json()
        self.assertEqual(submit_dup_data["sui_digest"], submit_data["sui_digest"])
        self.assertEqual(submit_dup_data["status"], "SUCCESS")

if __name__ == "__main__":
    unittest.main()
