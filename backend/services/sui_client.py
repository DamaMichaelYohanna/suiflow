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
        Returns the derived address and the base64 serialized private key (keystring).
        """
        mnemonic, keypair = create_new_keypair(SignatureScheme.ED25519)
        address = SuiAddress.from_bytes(keypair.to_bytes())
        return {
            "address": address.address,
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

        gas_budget = 20_000_000
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

sui_client = SuiClientService()
