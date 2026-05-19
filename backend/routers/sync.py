from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
import database, models, schemas
from routers.payments import process_sui_transaction
from services.auth_utils import get_current_user

router = APIRouter()

@router.post("/offline", status_code=202)
async def sync_offline_queue(
    payload: schemas.OfflineSyncPayload,
    background_tasks: BackgroundTasks,
    db: Session = Depends(database.get_db),
    current_user: models.User = Depends(get_current_user)
):
    processed_count = 0
    for payment in payload.transactions:
        receiver = db.query(models.User).filter(models.User.phone_number == payment.receiver_phone).first()
        if not receiver:
            continue # In prod we might handle non-registered numbers via links
            
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

        background_tasks.add_task(
            process_sui_transaction, 
            db, 
            history.id, 
            current_user.wallet.address, 
            receiver.wallet.address, 
            payment.amount, 
            payment.programmable_split
        )
        processed_count += 1

    return {"message": f"Successfully queued {processed_count} transactions for blockchain sync"}
