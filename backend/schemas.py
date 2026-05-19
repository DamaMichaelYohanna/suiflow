from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class UserBase(BaseModel):
    phone_number: str
    username: str
    full_name: Optional[str] = None

class UserCreate(BaseModel):
    phone_number: Optional[str] = None
    username: str
    password: str
    full_name: Optional[str] = None
    social_id: Optional[str] = None
    auth_method: str = "PHONE"

class UserLogin(BaseModel):
    phone_number: str
    password: str

class ZKLoginRequest(BaseModel):
    jwt: str

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenData(BaseModel):
    user_id: Optional[str] = None
    phone_number: Optional[str] = None

class WalletSchema(BaseModel):
    address: str

    class Config:
        from_attributes = True

class VaultSchema(BaseModel):
    id: int
    name: str
    object_id: str

    class Config:
        from_attributes = True

class VaultCreate(BaseModel):
    name: str

class ProgrammableRuleSchema(BaseModel):
    id: int
    rule_type: str
    target_vault_id: Optional[int] = None
    percentage: float
    is_active: bool

    class Config:
        from_attributes = True

class ProgrammableRuleCreate(BaseModel):
    rule_type: str
    target_vault_id: Optional[int] = None
    percentage: float

class User(UserBase):
    id: int
    is_active: bool
    wallet: Optional[WalletSchema] = None
    vaults: List[VaultSchema] = []
    rules: List[ProgrammableRuleSchema] = []
    social_id: Optional[str] = None
    auth_method: str

    class Config:
        from_attributes = True

class LoginResponse(BaseModel):
    user: User
    token: Token

class PaymentRequest(BaseModel):
    receiver_phone: str
    amount: float
    is_offline_queue: bool = False
    programmable_split: Optional[dict] = None # e.g. {"savings": 20}

class TransactionResponse(BaseModel):
    id: int
    status: str
    amount: float
    timestamp: datetime
    sui_digest: Optional[str] = None

    class Config:
        from_attributes = True

class OfflineSyncPayload(BaseModel):
    transactions: List[PaymentRequest]

# Sponsored Transaction Pipeline Schemas
class TransactionIntentRequest(BaseModel):
    sender_phone: str # Can also be username
    receiver_phone: str # Can also be username
    amount: float
    programmable_split: Optional[dict] = None

class TransactionIntentResponse(BaseModel):
    intent_id: str
    sender_address: str
    receiver_address: str
    amount: float
    status: str

class TransactionBuildRequest(BaseModel):
    intent_id: str

class TransactionBuildResponse(BaseModel):
    tx_bytes: str
    intent_id: str
    estimated_gas: int

class TransactionSponsorRequest(BaseModel):
    intent_id: str

class TransactionSponsorResponse(BaseModel):
    tx_bytes: str
    sponsor_signature: str

class TransactionSubmitRequest(BaseModel):
    intent_id: str
    user_signature: str

class TransactionSubmitResponse(BaseModel):
    sui_digest: str
    status: str
    intent_id: str

class UserLookupResponse(BaseModel):
    username: str
    phone_number: Optional[str] = None
    full_name: Optional[str] = None
    wallet_address: Optional[str] = None

class TransactionHistoryItem(BaseModel):
    id: int
    direction: str          # "sent" | "received"
    counterpart_name: str
    counterpart_phone: Optional[str] = None
    amount: float
    status: str
    timestamp: datetime
    sui_digest: Optional[str] = None

    class Config:
        from_attributes = True
