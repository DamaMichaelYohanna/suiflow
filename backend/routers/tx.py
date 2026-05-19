from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
import database, models, schemas
import uuid
import json
from services.sui_client import sui_client

router = APIRouter()

@router.post("/intent", response_model=schemas.TransactionIntentResponse)
def create_transaction_intent(
    request: schemas.TransactionIntentRequest,
    db: Session = Depends(database.get_db)
):
    """
    1. CLIENT INTENT PHASE
    Resolves sender and receiver wallets by phone or username, generates a unique intent_id, 
    and saves the intent in the database.
    """
    # Resolve sender
    sender = db.query(models.User).filter(
        (models.User.phone_number == request.sender_phone) | 
        (models.User.username == request.sender_phone)
    ).first()
    if not sender:
        raise HTTPException(status_code=404, detail=f"Sender '{request.sender_phone}' not found")

    # Resolve receiver
    receiver = db.query(models.User).filter(
        (models.User.phone_number == request.receiver_phone) | 
        (models.User.username == request.receiver_phone)
    ).first()
    if not receiver:
        raise HTTPException(status_code=404, detail=f"Receiver '{request.receiver_phone}' not found")

    if sender.id == receiver.id:
        raise HTTPException(status_code=400, detail="Cannot send transactions to yourself")

    # Generate unique intent identifier
    intent_id = f"intent_{uuid.uuid4().hex}"

    # Serialize split rules if present
    split_rules = json.dumps(request.programmable_split) if request.programmable_split else None

    # Record intent in history
    history = models.TransactionHistory(
        sender_id=sender.id,
        receiver_id=receiver.id,
        amount=request.amount,
        status="INTENT_CREATED",
        intent_id=intent_id,
        is_programmable=bool(request.programmable_split),
        split_rules=split_rules
    )
    db.add(history)
    db.commit()
    db.refresh(history)

    return schemas.TransactionIntentResponse(
        intent_id=intent_id,
        sender_address=sender.wallet.address,
        receiver_address=receiver.wallet.address,
        amount=request.amount,
        status=history.status
    )


@router.post("/build", response_model=schemas.TransactionBuildResponse)
def build_sponsored_transaction(
    request: schemas.TransactionBuildRequest,
    db: Session = Depends(database.get_db)
):
    """
    2. TRANSACTION BUILD PHASE
    Retrieves the intent, resolves recipient savings vault if split rules are active, 
    composes the Programmable Transaction Block (PTB) using pysui, and serializes the tx_bytes.
    """
    history = db.query(models.TransactionHistory).filter(
        models.TransactionHistory.intent_id == request.intent_id
    ).first()
    if not history:
        raise HTTPException(status_code=404, detail="Transaction intent not found")

    # Get sender and receiver wallets
    sender_wallet = history.sender.wallet.address
    receiver_wallet = history.receiver.wallet.address

    try:
        split = json.loads(history.split_rules) if history.split_rules else None
    except Exception:
        split = None

    # Build PTB using the Payment Orchestration Layer
    try:
        from services.payment_orchestrator import payment_orchestrator
        tx_bytes, estimated_gas, split_config, resolved_vault_id = payment_orchestrator.resolve_rules_and_build_tx(
            db=db,
            sender_id=history.sender_id,
            receiver_id=history.receiver_id,
            amount=history.amount,
            client_split=split
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to build transaction block: {e}")

    # Update database record
    history.tx_bytes = tx_bytes
    history.gas_budget = estimated_gas
    history.status = "BUILT"
    db.commit()

    return schemas.TransactionBuildResponse(
        tx_bytes=tx_bytes,
        intent_id=request.intent_id,
        estimated_gas=estimated_gas
    )


@router.post("/sponsor", response_model=schemas.TransactionSponsorResponse)
def sponsor_transaction(
    request: schemas.TransactionSponsorRequest,
    db: Session = Depends(database.get_db)
):
    """
    3. SPONSORSHIP PHASE
    Signs the serialized transaction bytes as the Gas Sponsor using the backend relayer's key.
    """
    history = db.query(models.TransactionHistory).filter(
        models.TransactionHistory.intent_id == request.intent_id
    ).first()
    if not history:
        raise HTTPException(status_code=404, detail="Transaction intent not found")

    if not history.tx_bytes:
        raise HTTPException(status_code=400, detail="Transaction must be built before sponsoring")

    # Sign transaction bytes as gas sponsor
    try:
        sponsor_sig = sui_client.sign_as_sponsor(history.tx_bytes)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Sponsorship signing failed: {e}")

    # Update database record
    history.sponsor_signature = sponsor_sig
    history.status = "SPONSORED"
    db.commit()

    return schemas.TransactionSponsorResponse(
        tx_bytes=history.tx_bytes,
        sponsor_signature=sponsor_sig
    )


@router.post("/submit", response_model=schemas.TransactionSubmitResponse)
def submit_transaction(
    request: schemas.TransactionSubmitRequest,
    db: Session = Depends(database.get_db)
):
    """
    5. FINAL SUBMISSION PHASE
    Combines the user's signature with the sponsor's signature, validates execution status, 
    and broadcasts to the Sui network. Features retry-safe idempotency checks.
    """
    history = db.query(models.TransactionHistory).filter(
        models.TransactionHistory.intent_id == request.intent_id
    ).first()
    if not history:
        raise HTTPException(status_code=404, detail="Transaction intent not found")

    # Idempotency check: If transaction is already successfully completed, return cached result
    if history.status == "COMPLETED" and history.sui_digest:
        print(f"[IDEMPOTENCY] Returning cached digest for intent {request.intent_id}")
        return schemas.TransactionSubmitResponse(
            sui_digest=history.sui_digest,
            status="SUCCESS",
            intent_id=request.intent_id
        )

    if not history.tx_bytes or not history.sponsor_signature:
        raise HTTPException(status_code=400, detail="Transaction must be built and sponsored before submission")

    # Store user signature
    history.user_signature = request.user_signature

    # Submit transaction
    try:
        res = sui_client.submit_dual_signed_transaction(
            tx_bytes=history.tx_bytes,
            user_signature=request.user_signature,
            sponsor_signature=history.sponsor_signature
        )
    except Exception as e:
        history.status = "FAILED"
        db.commit()
        raise HTTPException(status_code=500, detail=f"Transaction broadcast failed: {e}")

    # Update final transaction status
    if res.get("status") == "SUCCESS":
        history.status = "COMPLETED"
        history.sui_digest = res["digest"]
    else:
        history.status = "FAILED"

    db.commit()

    return schemas.TransactionSubmitResponse(
        sui_digest=history.sui_digest if history.sui_digest else "failed_submission",
        status=res["status"],
        intent_id=request.intent_id
    )
