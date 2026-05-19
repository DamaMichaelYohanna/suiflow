from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
import database, models, schemas
from services.sui_client import sui_client
from services.auth_utils import get_current_user

router = APIRouter()

from services.payment_orchestrator import payment_orchestrator

async def process_sui_transaction(db: Session, history_id: int, sender_wallet: str, receiver_wallet: str, amount: float, split: dict):
    try:
        sender = db.query(models.User).join(models.Wallet).filter(models.Wallet.address == sender_wallet).first()
        receiver = db.query(models.User).join(models.Wallet).filter(models.Wallet.address == receiver_wallet).first()
        if not sender or not receiver:
            raise Exception("Sender or Receiver not found in database.")

        digest = await payment_orchestrator.execute_complete_pipeline(
            db=db,
            sender_id=sender.id,
            receiver_id=receiver.id,
            amount=amount,
            client_split=split
        )
        
        # Update DB on success
        history = db.query(models.TransactionHistory).filter(models.TransactionHistory.id == history_id).first()
        if history:
            history.status = "COMPLETED"
            history.sui_digest = digest
            db.commit()
            
            # TODO: Emit websocket notification to sender and receiver
            print(f"Transaction {history_id} completed. Digest: {digest}")
    except Exception as e:
        # Update DB on failure
        history = db.query(models.TransactionHistory).filter(models.TransactionHistory.id == history_id).first()
        if history:
            history.status = "FAILED"
            db.commit()
        print(f"Transaction {history_id} failed: {e}")


@router.post("/send", response_model=schemas.TransactionResponse)
async def send_payment(
    payment: schemas.PaymentRequest, 
    background_tasks: BackgroundTasks,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    if current_user.phone_number == payment.receiver_phone:
        raise HTTPException(status_code=400, detail="You cannot send money to yourself")

    receiver = db.query(models.User).filter(models.User.phone_number == payment.receiver_phone).first()

    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver not found")

    # Record history
    history = models.TransactionHistory(
        sender_id=current_user.id,
        receiver_id=receiver.id,
        amount=payment.amount,
        status="PENDING",
        is_programmable=bool(payment.programmable_split)
    )
    db.add(history)
    db.commit()
    db.refresh(history)

    # Delegate blockchain execution to background task to keep API fast
    background_tasks.add_task(
        process_sui_transaction, 
        db, 
        history.id, 
        current_user.wallet.address, 
        receiver.wallet.address, 
        payment.amount, 
        payment.programmable_split
    )

    return history
