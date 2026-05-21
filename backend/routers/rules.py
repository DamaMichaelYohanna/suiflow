from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List
import database, models, schemas
from services.auth_utils import get_current_user

router = APIRouter()

@router.get("/", response_model=List[schemas.ProgrammableRuleSchema])
def list_rules(
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """List all programmable rules for the authenticated user."""
    return current_user.rules

@router.post("/", response_model=schemas.ProgrammableRuleSchema)
def create_rule(
    rule: schemas.ProgrammableRuleCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Create a new programmable auto-savings rule."""
    if rule.percentage <= 0 or rule.percentage > 100:
        raise HTTPException(status_code=400, detail="Percentage must be between 0 and 100")

    # Validate that the target vault belongs to this user (if specified)
    if rule.target_vault_id is not None:
        vault = db.query(models.Vault).filter(
            models.Vault.id == rule.target_vault_id,
            models.Vault.owner_id == current_user.id
        ).first()
        if not vault:
            raise HTTPException(status_code=404, detail="Target vault not found or does not belong to you")

    # Validate total active percentage does not exceed 100
    existing_total = sum(
        r.percentage for r in current_user.rules if r.is_active
    )
    if existing_total + rule.percentage > 100:
        raise HTTPException(
            status_code=400,
            detail=f"Total active rule percentage would exceed 100% (current: {existing_total}%, adding: {rule.percentage}%)"
        )

    db_rule = models.ProgrammableRule(
        user_id=current_user.id,
        rule_type=rule.rule_type,
        target_vault_id=rule.target_vault_id,
        percentage=rule.percentage,
        is_active=True
    )
    db.add(db_rule)
    db.commit()
    db.refresh(db_rule)
    return db_rule

@router.put("/{rule_id}", response_model=schemas.ProgrammableRuleSchema)
def update_rule(
    rule_id: int,
    rule: schemas.ProgrammableRuleCreate,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Update an existing programmable rule."""
    db_rule = db.query(models.ProgrammableRule).filter(
        models.ProgrammableRule.id == rule_id,
        models.ProgrammableRule.user_id == current_user.id
    ).first()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Rule not found")

    if rule.percentage <= 0 or rule.percentage > 100:
        raise HTTPException(status_code=400, detail="Percentage must be between 0 and 100")

    # Validate target vault ownership
    if rule.target_vault_id is not None:
        vault = db.query(models.Vault).filter(
            models.Vault.id == rule.target_vault_id,
            models.Vault.owner_id == current_user.id
        ).first()
        if not vault:
            raise HTTPException(status_code=404, detail="Target vault not found or does not belong to you")

    # Validate total percentage excluding the rule being updated
    existing_total = sum(
        r.percentage for r in current_user.rules if r.is_active and r.id != rule_id
    )
    if existing_total + rule.percentage > 100:
        raise HTTPException(
            status_code=400,
            detail=f"Total active rule percentage would exceed 100% (current others: {existing_total}%, setting: {rule.percentage}%)"
        )

    db_rule.rule_type = rule.rule_type
    db_rule.target_vault_id = rule.target_vault_id
    db_rule.percentage = rule.percentage
    db.commit()
    db.refresh(db_rule)
    return db_rule

@router.delete("/{rule_id}")
def delete_rule(
    rule_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Delete a programmable rule."""
    db_rule = db.query(models.ProgrammableRule).filter(
        models.ProgrammableRule.id == rule_id,
        models.ProgrammableRule.user_id == current_user.id
    ).first()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Rule not found")

    db.delete(db_rule)
    db.commit()
    return {"status": "deleted", "rule_id": rule_id}

@router.patch("/{rule_id}/toggle")
def toggle_rule(
    rule_id: int,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Toggle a rule's active status on or off."""
    db_rule = db.query(models.ProgrammableRule).filter(
        models.ProgrammableRule.id == rule_id,
        models.ProgrammableRule.user_id == current_user.id
    ).first()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Rule not found")

    # If activating, validate total percentage
    if not db_rule.is_active:
        existing_total = sum(
            r.percentage for r in current_user.rules if r.is_active
        )
        if existing_total + db_rule.percentage > 100:
            raise HTTPException(
                status_code=400,
                detail=f"Cannot activate: total active percentage would exceed 100% (current: {existing_total}%, this rule: {db_rule.percentage}%)"
            )

    db_rule.is_active = not db_rule.is_active
    db.commit()
    db.refresh(db_rule)
    return {"status": "toggled", "rule_id": rule_id, "is_active": db_rule.is_active}
