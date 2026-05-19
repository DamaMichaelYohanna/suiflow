from sqlalchemy.orm import Session
import models
from services.sui_client import sui_client
from services.kms_vault import encrypt_private_key

class WalletService:
    def create_user_wallet_and_vaults(self, db: Session, user_id: int) -> models.Wallet:
        """
        Generates a new Sui Wallet for the user, encrypts the private key via KMS,
        and initializes default vaults (Savings, Investment) to keep auth logic clean.
        """
        # Generate Sui keypair
        wallet_data = sui_client.generate_wallet()
        
        # Encrypt the private key using the KMS mock wrapper
        encrypted_pk = encrypt_private_key(wallet_data["private_key"])
        
        # Create Wallet record
        wallet = models.Wallet(
            address=wallet_data["address"],
            encrypted_keypair=encrypted_pk,
            owner_id=user_id
        )
        db.add(wallet)
        
        # Initialize default Vaults
        savings_vault = models.Vault(
            name="Savings", 
            object_id=f"vault_{user_id}_savings", 
            owner_id=user_id
        )
        investment_vault = models.Vault(
            name="Investment", 
            object_id=f"vault_{user_id}_invest", 
            owner_id=user_id
        )
        db.add(savings_vault)
        db.add(investment_vault)
        
        db.commit()
        return wallet

wallet_service = WalletService()
