import os
import asyncio
import uuid
import base64
from pysui import SuiConfig, SyncClient
from pysui.sui.sui_crypto import create_new_keypair, SignatureScheme, SuiKeyPair, keypair_from_keystring
from pysui.sui.sui_types.address import SuiAddress

# Monkey-patch pysui's missing BCS constant to bypass open library bug
from pysui.sui.sui_types import bcs
if not hasattr(bcs, "TYPETAG_VECTOR_DEPTH_MAX"):
    bcs.TYPETAG_VECTOR_DEPTH_MAX = 8

# Initialize actual Sui client. Supporting both environment variables (Vercel) and local configs.
client = None
config = None

sui_sponsor_key = os.environ.get("SUI_SPONSOR_KEY")
sui_rpc_url = os.environ.get("SUI_RPC_URL", "https://fullnode.testnet.sui.io:443")

if sui_sponsor_key:
    try:
        config = SuiConfig.user_config(rpc_url=sui_rpc_url)
        config.add_keypair_from_keystring(keystring=sui_sponsor_key, install=False, make_active=True)
        client = SyncClient(config)
        print(f"[SUI SDK CLIENT] Serverless Active address: {config.active_address}")
    except Exception as e:
        print(f"[SUI SDK CLIENT] Failed to initialize from SUI_SPONSOR_KEY env var: {e}")

if not client:
    try:
        config = SuiConfig.default_config()
        client = SyncClient(config)
        print(f"[SUI SDK CLIENT] Local Active address: {config.active_address}")
    except Exception as e:
        print(f"[SUI SDK CLIENT] Failed to load local Sui configuration (can be ignored on Vercel if SUI_SPONSOR_KEY is set): {e}")

class SuiClientService:
    def __init__(self):
        self.network = "local" if (config and config.rpc_url and "127.0.0.1" in config.rpc_url) else "testnet"


    def generate_wallet(self) -> dict:
        """
        Generates a new Sui Keypair using the pysui cryptographic suite.
        Returns the derived address (zero-padded to 66 chars) and the base64 serialized private key (keystring).
        """
        mnemonic, keypair = create_new_keypair(SignatureScheme.ED25519)

        # Derive the canonical Sui address using SuiAddress.from_bytes(keypair.to_bytes())
        # which correctly hashes the scheme flag and public key.
        from pysui.sui.sui_types.address import SuiAddress
        raw_address = str(SuiAddress.from_bytes(keypair.to_bytes()))

        # Ensure it is always a properly zero-padded 64-char hex string prefixed with 0x
        hex_part = raw_address.lstrip("0x").lstrip("0X")
        padded_address = "0x" + hex_part.zfill(64)

        print(f"[WALLET GEN] Generated address: {padded_address}")

        return {
            "address": padded_address,
            "private_key": keypair.serialize()
        }


    def register_user_on_chain(self, phone_number: str, display_name: str, wallet_address: str):
        """
        Registers the user's phone-to-wallet mapping on-chain using the AdminCap.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized. Please configure SUI_SPONSOR_KEY in Vercel environment variables or ensure local client.yaml is present.")
        from pysui.sui.sui_txn import SyncTransaction

        from pysui import ObjectID
        package_id = os.environ["SUIFLOW_PACKAGE_ID"]
        registry_id = ObjectID(os.environ["SUIFLOW_REGISTRY_ID"])
        admin_cap_id = ObjectID(os.environ["SUIFLOW_ADMIN_CAP_ID"])

        txn = SyncTransaction(client=client)
        txn.signer_block.sender = client.config.active_address

        phone_bytes = phone_number.encode('utf-8')

        txn.move_call(
            target=f"{package_id}::wallet_registry::register_user",
            arguments=[
                admin_cap_id,
                registry_id,
                list(phone_bytes),
                display_name,
                SuiAddress(wallet_address)
            ]
        )

        res = txn.execute()
        if res.is_err():
            raise Exception(f"On-chain user registration failed: {res.result_string}")
        
        print(f"[SUI SDK CLIENT] Registered user {phone_number} on-chain. Digest: {res.result_data.digest}")

    def get_sui_balance(self, wallet_address: str) -> float:
        """
        Fetches the total SUI balance for the given address by summing all SUI coins.
        Returns the balance in SUI (not MIST).
        """
        if not client:
            print("[SUI SDK CLIENT] Client not initialized, returning 0.0 balance.")
            return 0.0
            
        try:
            res = client.get_gas(SuiAddress(wallet_address))
            if res.is_ok() and res.result_data.data:
                total_mist = sum(int(coin.balance) for coin in res.result_data.data)
                return total_mist / 1_000_000_000.0
            return 0.0
        except Exception as e:
            print(f"[SUI SDK CLIENT] Failed to fetch balance for {wallet_address}: {e}")
            return 0.0

    def build_sponsored_tx_bytes(
        self, 
        sender_address: str, 
        receiver_address: str, 
        amount: float, 
        split: dict = None, 
        receiver_vault_id: str = None,
        receiver_wallet_address: str = None
    ) -> tuple[str, int]:
        """
        Builds a Sponsored Programmable Transaction Block (PTB) using pysui.
        Pushes gas fees to the sponsor's wallet while keeping the sender as the user.
        Strictly requires the sender to have a valid SUI coin.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized. Please configure SUI_SPONSOR_KEY in Vercel environment variables or ensure local client.yaml is present.")
        from pysui.sui.sui_txn import SyncTransaction

        txn = SyncTransaction(client=client)
        
        # Set sender and sponsor addresses
        txn.signer_block.sender = SuiAddress(sender_address)
        sponsor_address = client.config.active_address
        txn.signer_block.sponsor = sponsor_address

        # Convert amount to MIST
        amount_in_mist = int(amount * 1_000_000_000)

        # Retrieve package/object IDs from configuration or environment
        from pysui import ObjectID
        package_id = os.environ["SUIFLOW_PACKAGE_ID"]
        registry_id = ObjectID(os.environ["SUIFLOW_REGISTRY_ID"])
        payment_store_id = ObjectID(os.environ["SUIFLOW_PAYMENT_STORE_ID"])
        asset_whitelist_id = ObjectID(os.environ["SUIFLOW_ASSET_WHITELIST_ID"])

        # Resolve sender coins for the payment.
        user_coin_object = None
        res = client.get_gas(SuiAddress(sender_address))
        if not res.is_ok() or not res.result_data.data:
            raise ValueError(f"Sender '{sender_address}' has no gas/coins to transfer. Faucet funding required.")

        for coin in res.result_data.data:
            if int(coin.balance) >= amount_in_mist:
                user_coin_object = ObjectID(coin.object_id)
                break

        if not user_coin_object:
            raise ValueError(f"Sender '{sender_address}' has no single SUI coin with balance >= {amount_in_mist} MIST.")

        split_coin = txn.split_coin(coin=user_coin_object, amounts=[amount_in_mist])

        # Route dynamically based on programmable flow rules
        if split and receiver_vault_id:
            savings_pct = int(split.get("savings", 0))
            dest_wallet = receiver_wallet_address or receiver_address
            txn.move_call(
                target=f"{package_id}::programmable_flows::split_to_vault_and_wallet",
                arguments=[
                    split_coin,
                    ObjectID(receiver_vault_id),
                    savings_pct,
                    SuiAddress(dest_wallet)
                ],
                type_arguments=["0x2::sui::SUI"]
            )
        else:
            intent_id_str = f"intent_{uuid.uuid4().hex[:12]}"
            phone_bytes = receiver_address.encode('utf-8')
            txn.move_call(
                target=f"{package_id}::payment::send_payment",
                arguments=[
                    asset_whitelist_id,
                    payment_store_id,
                    registry_id,
                    intent_id_str,
                    list(phone_bytes),
                    split_coin
                ],
                type_arguments=["0x2::sui::SUI"]
            )

        gas_budget = 5_000_000
        txn_data = txn._build_for_execute(gas_budget=str(gas_budget))
        tx_bytes = base64.b64encode(txn_data.serialize()).decode()

        return tx_bytes, gas_budget

    def sign_as_sponsor(self, tx_bytes: str) -> str:
        """
        Signs transaction bytes as the Gas Sponsor using the backend relayer's keys.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized. Please configure SUI_SPONSOR_KEY in Vercel environment variables or ensure local client.yaml is present.")
        # Get sponsor keypair
        sponsor_address = client.config.active_address
        sponsor_keypair = client.config.keypair_for_address(sponsor_address)
        
        # Sign the base64 transaction bytes representation
        sig = sponsor_keypair.new_sign_secure(tx_bytes)
        return sig.value

    def submit_dual_signed_transaction(self, tx_bytes: str, user_signature: str, sponsor_signature: str) -> dict:
        """
        Submits pre-signed transaction bytes with both User and Sponsor signatures to the Sui RPC.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized. Please configure SUI_SPONSOR_KEY in Vercel environment variables or ensure local client.yaml is present.")
        from pysui.sui.sui_builders.exec_builders import ExecuteTransaction
        from pysui.sui.sui_builders.base_builder import SuiRequestType
        from pysui.sui.sui_types.scalars import SuiSignature
        from pysui.sui.sui_types.collections import SuiArray

        # Assemble both signatures into a SuiArray
        signatures = SuiArray([SuiSignature(user_signature), SuiSignature(sponsor_signature)])

        # Construct raw submission request
        exec_tx = ExecuteTransaction(
            tx_bytes=tx_bytes,
            signatures=signatures,
            request_type=SuiRequestType.WAITFORLOCALEXECUTION
        )

        # Broadcast transaction to RPC node
        result = client.execute(exec_tx)
        if result.is_err():
            raise Exception(f"Sui transaction submission failed: {result.result_string}")

        data = result.result_data
        digest = getattr(data, "digest", None)
        if not digest:
            raise ValueError("No transaction digest returned from transaction execution.")

        # Check effects execution status
        status = "SUCCESS"
        if hasattr(data, "effects") and hasattr(data.effects, "status"):
            eff_status = data.effects.status
            if getattr(eff_status, "status", "success") != "success":
                status = "FAILED"
                print(f"[SUI SDK CLIENT] Transaction failed on-chain! Status: {getattr(eff_status, 'status', 'error')}, Error: {getattr(eff_status, 'error', 'Unknown')}")

        return {
            "digest": digest,
            "status": status
        }

    async def execute_ptb(self, sender_address: str, sender_private_key: str, receiver_address: str, amount: float, programmable_split: dict = None, receiver_wallet_address: str = None) -> str:
        """
        Backward compatibility wrapper for legacy router endpoints.
        Delegates to the new multi-phase transaction builder and signer.
        """
        # Build transaction bytes
        tx_bytes, _ = self.build_sponsored_tx_bytes(
            sender_address=sender_address,
            receiver_address=receiver_address,
            receiver_wallet_address=receiver_wallet_address,
            amount=amount,
            split=programmable_split
        )
        
        # Sign as gas sponsor
        sponsor_sig = self.sign_as_sponsor(tx_bytes)
        
        # Load user private key and sign
        # Temporarily register sender private key in client config if not present
        try:
            client.config.add_keypair_from_keystring(keystring=sender_private_key, install=False, make_active=False)
        except ValueError:
            pass
        
        user_keypair = client.config.keypair_for_address(SuiAddress(sender_address))
        user_sig = user_keypair.new_sign_secure(tx_bytes).value
        
        # Submit
        res = self.submit_dual_signed_transaction(tx_bytes, user_sig, sponsor_sig)
        if res.get("status") != "SUCCESS":
            raise Exception("PTB execution on-chain failed (effects status is FAILED)")
            
        return res["digest"]

    def create_vault_on_chain(self, user_address: str, user_private_key: str) -> dict:
        """
        Creates a new Vault on-chain using a sponsored transaction.
        Returns a dict with the created Vault's object ID and VaultCap object ID.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized. Please configure SUI_SPONSOR_KEY.")
        from pysui.sui.sui_txn import SyncTransaction
        from pysui import SuiAddress, ObjectID

        # Build txn
        txn = SyncTransaction(client=client)
        txn.signer_block.sender = SuiAddress(user_address)
        txn.signer_block.sponsor = client.config.active_address

        package_id = os.environ["SUIFLOW_PACKAGE_ID"]
        txn.move_call(
            target=f"{package_id}::vaults::create_vault",
            arguments=[],
            type_arguments=["0x2::sui::SUI"]
        )

        gas_budget = 5_000_000
        txn_data = txn._build_for_execute(gas_budget=str(gas_budget))
        tx_bytes = base64.b64encode(txn_data.serialize()).decode()
        sponsor_sig = self.sign_as_sponsor(tx_bytes)

        # Temporarily register user keypair in config if needed to sign
        try:
            client.config.add_keypair_from_keystring(keystring=user_private_key, install=False, make_active=False)
        except ValueError:
            pass

        user_keypair = client.config.keypair_for_address(SuiAddress(user_address))
        user_sig = user_keypair.new_sign_secure(tx_bytes).value

        # Submit dual-signed txn
        from pysui.sui.sui_builders.exec_builders import ExecuteTransaction
        from pysui.sui.sui_builders.base_builder import SuiRequestType
        from pysui.sui.sui_types.scalars import SuiSignature
        from pysui.sui.sui_types.collections import SuiArray

        signatures = SuiArray([SuiSignature(user_sig), SuiSignature(sponsor_sig)])
        exec_tx = ExecuteTransaction(
            tx_bytes=tx_bytes,
            signatures=signatures,
            request_type=SuiRequestType.WAITFORLOCALEXECUTION
        )

        result = client.execute(exec_tx)
        if result.is_err():
            raise Exception(f"Sui transaction submission failed: {result.result_string}")

        data = result.result_data
        effects = getattr(data, "effects", None)
        if not effects or not hasattr(effects, "created"):
            raise ValueError("No created objects in transaction effects.")

        # Parse created objects to find the shared Vault and the owned VaultCap
        vault_id = None
        vault_cap_id = None
        for created in getattr(effects, "created", []):
            owner = created.owner
            if isinstance(owner, dict) and ("initial_shared_version" in owner or "Shared" in owner):
                vault_id = created.reference.object_id
            elif isinstance(owner, dict) and ("AddressOwner" in owner or "ObjectOwner" in owner):
                vault_cap_id = created.reference.object_id
            elif isinstance(owner, str):
                # String owner typically means address-owned (VaultCap)
                if vault_cap_id is None:
                    vault_cap_id = created.reference.object_id

        # Fallback: if we found multiple created objects but couldn't classify them
        created_list = getattr(effects, "created", [])
        if not vault_id and len(created_list) >= 1:
            vault_id = created_list[0].reference.object_id
        if not vault_cap_id and len(created_list) >= 2:
            vault_cap_id = created_list[1].reference.object_id

        if not vault_id:
            raise ValueError("Failed to locate created shared Vault object ID.")

        print(f"[SUI SDK CLIENT] Created on-chain vault {vault_id} (cap: {vault_cap_id}) for user {user_address}")
        return {
            "vault_id": vault_id,
            "vault_cap_id": vault_cap_id
        }

    def withdraw_from_vault_on_chain(
        self, user_address: str, user_private_key: str,
        vault_id: str, vault_cap_id: str, amount: float
    ) -> str:
        """
        Withdraws funds from an on-chain Vault using the VaultCap.
        Returns the transaction digest.
        """
        if not client or not config:
            raise RuntimeError("Sui SDK Client is not initialized.")
        from pysui.sui.sui_txn import SyncTransaction
        from pysui import SuiAddress, ObjectID

        amount_in_mist = int(amount * 1_000_000_000)

        txn = SyncTransaction(client=client)
        txn.signer_block.sender = SuiAddress(user_address)
        txn.signer_block.sponsor = client.config.active_address

        package_id = os.environ["SUIFLOW_PACKAGE_ID"]
        txn.move_call(
            target=f"{package_id}::vaults::withdraw",
            arguments=[
                ObjectID(vault_cap_id),
                ObjectID(vault_id),
                amount_in_mist,
            ],
            type_arguments=["0x2::sui::SUI"]
        )

        gas_budget = 5_000_000
        txn_data = txn._build_for_execute(gas_budget=str(gas_budget))
        tx_bytes = base64.b64encode(txn_data.serialize()).decode()
        sponsor_sig = self.sign_as_sponsor(tx_bytes)

        # Register user keypair if needed
        try:
            client.config.add_keypair_from_keystring(keystring=user_private_key, install=False, make_active=False)
        except ValueError:
            pass

        user_keypair = client.config.keypair_for_address(SuiAddress(user_address))
        user_sig = user_keypair.new_sign_secure(tx_bytes).value

        res = self.submit_dual_signed_transaction(tx_bytes, user_sig, sponsor_sig)
        if res.get("status") != "SUCCESS":
            raise Exception("Vault withdrawal transaction failed on-chain.")

        print(f"[SUI SDK CLIENT] Withdrew {amount} SUI from vault {vault_id}. Digest: {res['digest']}")
        return res["digest"]

    def get_vault_balance(self, object_id: str) -> float:
        """
        Queries the on-chain SUI balance inside a Vault object.
        """
        if not object_id or not object_id.startswith("0x"):
            return 0.0
            
        import urllib.request
        import json
        
        try:
            url = os.environ.get("SUI_RPC_URL", "https://fullnode.testnet.sui.io:443")
            payload = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "sui_getObject",
                "params": [
                    object_id,
                    {"showContent": True}
                ]
            }
            req = urllib.request.Request(
                url, 
                data=json.dumps(payload).encode(), 
                headers={'Content-Type': 'application/json'}
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                res_data = json.loads(response.read().decode())
                if "result" in res_data and "data" in res_data["result"]:
                    obj_data = res_data["result"]["data"]
                    if "content" in obj_data and "fields" in obj_data["content"]:
                        fields = obj_data["content"]["fields"]
                        if "balance" in fields:
                            val = fields["balance"]
                            if isinstance(val, dict) and "value" in val:
                                return float(val["value"]) / 1_000_000_000.0
                            elif isinstance(val, (int, float)):
                                return float(val) / 1_000_000_000.0
                            elif isinstance(val, str) and val.isdigit():
                                return float(val) / 1_000_000_000.0
            return 0.0
        except Exception as e:
            print(f"[SUI SDK CLIENT] Failed to fetch vault balance for {object_id}: {e}")
            return 0.0

sui_client = SuiClientService()
