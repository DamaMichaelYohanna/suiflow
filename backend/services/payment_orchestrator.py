import uuid
from sqlalchemy.orm import Session
import models
from services.sui_client import sui_client
from services.kms_vault import decrypt_private_key

class PaymentOrchestratorService:
    def resolve_rules_and_build_tx(
        self, 
        db: Session, 
        sender_id: int, 
        receiver_id: int, 
        amount: float, 
        client_split: dict = None
    ) -> tuple[str, int, dict, str]:
        """
        Orchestration Layer:
        1. Loads database-configured ProgrammableRules (or defaults to client split rules).
        2. Resolves recipient vault IDs based on rules.
        3. Builds the Sponsored PTB on-chain.
        Returns (tx_bytes, estimated_gas, split_config, receiver_vault_id).
        """
        sender = db.query(models.User).filter(models.User.id == sender_id).first()
        receiver = db.query(models.User).filter(models.User.id == receiver_id).first()
        
        if not sender or not receiver:
            raise ValueError("Sender or Receiver not found in database.")

        # Determine split configuration: prioritize client input, then fallback to db ProgrammableRules
        split_config = client_split
        receiver_vault_id = None

        if not split_config:
            # Query db rules for auto-saving split config
            rule = db.query(models.ProgrammableRule).filter(
                models.ProgrammableRule.user_id == receiver_id,
                models.ProgrammableRule.is_active == True
            ).first()
            if rule:
                split_config = {
                    "savings": int(rule.percentage)
                }
                if rule.target_vault:
                    receiver_vault_id = rule.target_vault.object_id

        # If we have a split config but no resolved vault yet, locate default "Savings" vault
        if split_config and not receiver_vault_id:
            vault = db.query(models.Vault).filter(
                models.Vault.owner_id == receiver_id,
                models.Vault.name == "Savings"
            ).first()
            if vault:
                receiver_vault_id = vault.object_id

        # If the resolved vault object ID is a mock string, dynamically create it on-chain now!
        if receiver_vault_id and not receiver_vault_id.startswith("0x"):
            try:
                print(f"[ORCHESTRATOR] Vault {receiver_vault_id} is a mock. Creating on-chain vault for receiver...")
                from services.kms_vault import decrypt_private_key
                receiver_pk = decrypt_private_key(receiver.wallet.encrypted_keypair)
                
                # Create vault on-chain
                real_vault_id = sui_client.create_vault_on_chain(
                    user_address=receiver.wallet.address,
                    user_private_key=receiver_pk
                )
                
                # Update database
                vault = db.query(models.Vault).filter(
                    models.Vault.owner_id == receiver_id,
                    models.Vault.object_id == receiver_vault_id
                ).first()
                if vault:
                    vault.object_id = real_vault_id
                    db.commit()
                    receiver_vault_id = real_vault_id
                    print(f"[ORCHESTRATOR] Successfully migrated mock vault to on-chain object {real_vault_id}")
            except Exception as e:
                print(f"[ORCHESTRATOR] Warning: Failed to lazily migrate mock vault: {e}")

        sender_wallet = sender.wallet.address
        receiver_wallet = receiver.wallet.address
        receiver_identifier = receiver.phone_number if receiver.phone_number else receiver.username

        # Check if receiver is registered on-chain. If not, lazily register them now using the sponsor's admin cap.
        if not getattr(receiver, "is_registered_on_chain", False):
            try:
                print(f"[ORCHESTRATOR] Lazy-registering recipient {receiver_identifier} on-chain...")
                sui_client.register_user_on_chain(
                    phone_number=receiver_identifier,
                    display_name=receiver.full_name or receiver.username,
                    wallet_address=receiver_wallet
                )
                receiver.is_registered_on_chain = True
                db.commit()
            except Exception as e:
                # If already registered on-chain but DB didn't reflect it, mark as True.
                # EPhoneAlreadyRegistered maps to code 600 or the error string.
                if "EPhoneAlreadyRegistered" in str(e) or "600" in str(e):
                    print(f"[ORCHESTRATOR] Recipient {receiver_identifier} was already registered on-chain.")
                    receiver.is_registered_on_chain = True
                    db.commit()
                else:
                    print(f"[ORCHESTRATOR] Lazy-registering on-chain failed: {e}")

        # Build transaction bytes via sui client
        tx_bytes, estimated_gas = sui_client.build_sponsored_tx_bytes(
            sender_address=sender_wallet,
            receiver_address=receiver_identifier,
            receiver_wallet_address=receiver_wallet,
            amount=amount,
            split=split_config,
            receiver_vault_id=receiver_vault_id
        )

        return tx_bytes, estimated_gas, split_config, receiver_vault_id

    async def execute_complete_pipeline(
        self, 
        db: Session, 
        sender_id: int, 
        receiver_id: int, 
        amount: float, 
        client_split: dict = None
    ) -> str:
        """
        Legacy/Simple payment wrapper. Performs building, signing, and submission in one flow.
        """
        sender = db.query(models.User).filter(models.User.id == sender_id).first()
        receiver = db.query(models.User).filter(models.User.id == receiver_id).first()
        
        # Build transaction bytes with rule orchestration
        tx_bytes, _, split_config, receiver_vault_id = self.resolve_rules_and_build_tx(
            db, sender_id, receiver_id, amount, client_split
        )

        # Sponsor signs
        sponsor_sig = sui_client.sign_as_sponsor(tx_bytes)

        # Decrypt user's key pair from KMS
        encrypted_pk = sender.wallet.encrypted_keypair
        decrypted_pk = decrypt_private_key(encrypted_pk)

        # Register keypair in client config if needed
        from pysui import SuiAddress
        try:
            from services.sui_client import client
            client.config.add_keypair_from_keystring(keystring=decrypted_pk, install=False, make_active=False)
        except ValueError:
            pass

        # Sign as user
        user_keypair = client.config.keypair_for_address(SuiAddress(sender.wallet.address))
        user_sig = user_keypair.new_sign_secure(tx_bytes).value

        # Submit dual-signed transaction
        res = sui_client.submit_dual_signed_transaction(tx_bytes, user_sig, sponsor_sig)
        if res.get("status") != "SUCCESS":
            raise Exception("Payment orchestration PTB execution failed.")

        return res["digest"]

payment_orchestrator = PaymentOrchestratorService()
