from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
import database, models, schemas
from services.sui_client import sui_client
from services.kms_vault import decrypt_private_key
from services.auth_utils import get_current_user

router = APIRouter()

@router.post("/", response_model=schemas.VaultSchema)
def create_vault(
    vault: schemas.VaultCreate, 
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    # Check if vault name already exists for this user
    existing_vault = db.query(models.Vault).filter(
        models.Vault.owner_id == current_user.id, 
        models.Vault.name == vault.name
    ).first()
    if existing_vault:
        raise HTTPException(status_code=400, detail="Vault with this name already exists")
    
    # Create the vault on-chain using a sponsored transaction
    try:
        user_pk = decrypt_private_key(current_user.wallet.encrypted_keypair)
        print(f"[VAULTS ROUTER] Creating on-chain vault '{vault.name}' for user {current_user.wallet.address}...")
        object_id = sui_client.create_vault_on_chain(
            user_address=current_user.wallet.address,
            user_private_key=user_pk
        )
    except Exception as e:
        print(f"[VAULTS ROUTER] Warning: Failed to create on-chain vault: {e}")
        # Fallback to simulated ID if blockchain transaction fails
        safe_name = vault.name.lower().replace(" ", "_")
        object_id = f"vault_{current_user.id}_{safe_name}"
    
    db_vault = models.Vault(
        name=vault.name,
        object_id=object_id,
        owner_id=current_user.id
    )
    db.add(db_vault)
    db.commit()
    db.refresh(db_vault)
    
    # Populate balance for the schema response
    db_vault.balance = 0.0
    return db_vault

@router.get("/", response_model=List[schemas.VaultSchema])
def list_vaults(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    # Populate on-chain balances dynamically for each vault
    for v in current_user.vaults:
        v.balance = sui_client.get_vault_balance(v.object_id)
    return current_user.vaults
