from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
import database, models, schemas
from services.sui_client import sui_client
from services.auth_utils import create_access_token, get_password_hash, verify_password, get_current_user

router = APIRouter()

@router.post("/register", response_model=schemas.LoginResponse)
def register_user(user: schemas.UserCreate, db: Session = Depends(database.get_db)):
    # Check if user exists
    if user.phone_number:
        db_user = db.query(models.User).filter(models.User.phone_number == user.phone_number).first()
        if db_user:
            raise HTTPException(status_code=400, detail="Phone number already registered")
    
    if user.social_id:
        db_user = db.query(models.User).filter(models.User.social_id == user.social_id).first()
        if db_user:
            raise HTTPException(status_code=400, detail="Social account already registered")

    db_user_username = db.query(models.User).filter(models.User.username == user.username).first()
    if db_user_username:
        raise HTTPException(status_code=400, detail="Username already taken")

    # Create User
    new_user = models.User(
        phone_number=user.phone_number, 
        username=user.username,
        hashed_password=get_password_hash(user.password),
        full_name=user.full_name,
        social_id=user.social_id,
        auth_method=user.auth_method
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    # Automatically generate a Sui Wallet for the user and default Vaults (Wallet Abstraction)
    from services.wallet_service import wallet_service
    wallet = wallet_service.create_user_wallet_and_vaults(db, new_user.id)
    
    db.refresh(new_user)

    # Register canonical identity mapping on-chain using AdminCap (Phone if present, otherwise username)
    try:
        canonical_identifier = new_user.phone_number if new_user.phone_number else new_user.username
        sui_client.register_user_on_chain(
            phone_number=canonical_identifier,
            display_name=new_user.full_name or new_user.username,
            wallet_address=wallet.address
        )
    except Exception as e:
        print(f"[AUTH ROUTER] Warning: On-chain registration failed: {e}")

    # Generate Token using canonical user.id
    access_token = create_access_token(data={"sub": str(new_user.id)})
    token = schemas.Token(access_token=access_token, token_type="bearer")

    return schemas.LoginResponse(user=new_user, token=token)

@router.post("/login", response_model=schemas.LoginResponse)
def login_user(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(database.get_db)):
    # Swagger UI sends 'username', which we treat as the phone_number
    user = db.query(models.User).filter(models.User.phone_number == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect phone number or password")
    
    # Generate Token using canonical user.id
    access_token = create_access_token(data={"sub": str(user.id)})
    token = schemas.Token(access_token=access_token, token_type="bearer")

    return schemas.LoginResponse(user=user, token=token)

@router.post("/zklogin", response_model=schemas.LoginResponse)
def zklogin_user(request: schemas.ZKLoginRequest, db: Session = Depends(database.get_db)):
    # In a real app, we would verify the JWT using google-auth or python-jose
    # For MVP/Hackathon demo, we extract a mock identity from the "jwt" string
    social_id = request.jwt # In prod: verify_jwt(request.jwt)["sub"]
    
    user = db.query(models.User).filter(models.User.social_id == social_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Social user not found. Please sign up.")
    
    # Generate Token using canonical user.id
    access_token = create_access_token(data={"sub": str(user.id)})
    token = schemas.Token(access_token=access_token, token_type="bearer")

    return schemas.LoginResponse(user=user, token=token)

@router.get("/user/{phone_number}", response_model=schemas.User)
def get_user(phone_number: str, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.phone_number == phone_number).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@router.get("/lookup", response_model=schemas.UserLookupResponse)
def lookup_user(query: str, db: Session = Depends(database.get_db)):
    """
    Search for a user by phone number or username to confirm identity before sending.
    Rate limiting: Rate limited by IP in middleware to prevent user enumeration attacks.
    """
    user = db.query(models.User).filter(
        (models.User.phone_number == query) | (models.User.username == query)
    ).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Return minimized data to protect user privacy
    return schemas.UserLookupResponse(
        username=user.username,
        phone_number=user.phone_number,
        full_name=user.full_name,
        wallet_address=user.wallet.address if user.wallet else None
    )

@router.get("/balance")
def get_balance(db: Session = Depends(database.get_db), current_user: models.User = Depends(get_current_user)):
    """
    Fetch the actual SUI balance for the authenticated user.
    """
    if not current_user.wallet:
        return {"balance": 0.0}
    
    balance = sui_client.get_sui_balance(current_user.wallet.address)
    return {"balance": balance}
