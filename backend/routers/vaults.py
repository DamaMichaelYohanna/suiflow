from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
import database, models, schemas
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
    
    # In a real app, this would trigger a Sui transaction to create the vault on-chain.
    # For MVP, we simulate the object_id generation.
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
    return db_vault

@router.get("/", response_model=List[schemas.VaultSchema])
def list_vaults(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    return current_user.vaults
