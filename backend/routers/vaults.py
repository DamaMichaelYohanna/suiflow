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
        result = sui_client.create_vault_on_chain(
            user_address=current_user.wallet.address,
            user_private_key=user_pk
        )
        object_id = result["vault_id"]
        vault_cap_id = result.get("vault_cap_id")
    except Exception as e:
        print(f"[VAULTS ROUTER] Failed to create on-chain vault: {e}")
        raise HTTPException(
            status_code=502, 
            detail=f"Failed to create vault on the Sui blockchain: {e}"
        )
    
    db_vault = models.Vault(
        name=vault.name,
        object_id=object_id,
        vault_cap_id=vault_cap_id,
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

@router.post("/{vault_id}/withdraw")
def withdraw_from_vault(
    vault_id: int,
    request: schemas.VaultWithdrawRequest,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Withdraw funds from a user's vault back to their wallet via the blockchain."""
    vault = db.query(models.Vault).filter(
        models.Vault.id == vault_id,
        models.Vault.owner_id == current_user.id
    ).first()
    
    if not vault:
        raise HTTPException(status_code=404, detail="Vault not found")
    
    if not vault.object_id or not vault.object_id.startswith("0x"):
        raise HTTPException(status_code=400, detail="Vault has no valid on-chain object ID")
    
    if not vault.vault_cap_id:
        raise HTTPException(
            status_code=400, 
            detail="Vault capability (VaultCap) not found. This vault may have been created before withdrawal support was added."
        )
    
    if request.amount <= 0:
        raise HTTPException(status_code=400, detail="Withdrawal amount must be greater than zero")
    
    # Check on-chain balance before attempting withdrawal
    current_balance = sui_client.get_vault_balance(vault.object_id)
    if request.amount > current_balance:
        raise HTTPException(
            status_code=400, 
            detail=f"Insufficient vault balance. Available: {current_balance:.4f} SUI, Requested: {request.amount:.4f} SUI"
        )
    
    try:
        user_pk = decrypt_private_key(current_user.wallet.encrypted_keypair)
        digest = sui_client.withdraw_from_vault_on_chain(
            user_address=current_user.wallet.address,
            user_private_key=user_pk,
            vault_id=vault.object_id,
            vault_cap_id=vault.vault_cap_id,
            amount=request.amount
        )
    except Exception as e:
        print(f"[VAULTS ROUTER] Withdrawal failed: {e}")
        raise HTTPException(status_code=502, detail=f"Withdrawal failed on-chain: {e}")
    
    return {
        "status": "SUCCESS",
        "sui_digest": digest,
        "vault_id": vault_id,
        "amount_withdrawn": request.amount
    }
