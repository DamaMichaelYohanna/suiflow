import database, models
from sqlalchemy.orm import Session
from routers.payments import get_transaction_history
from schemas import TransactionHistoryItem

db = database.SessionLocal()
user = db.query(models.User).filter(models.User.phone_number == "08160535033").first()
if user:
    try:
        txns = get_transaction_history(db=db, current_user=user)
        print("Success:", txns)
    except Exception as e:
        import traceback
        traceback.print_exc()
else:
    print("User not found")
