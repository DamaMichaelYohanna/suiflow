from sqlalchemy import Boolean, Column, ForeignKey, Integer, String, Float, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    phone_number = Column(String, unique=True, index=True)
    full_name = Column(String, nullable=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    is_active = Column(Boolean, default=True)
    social_id = Column(String, unique=True, nullable=True) # For zkLogin (Google/Apple ID)
    auth_method = Column(String, default="PHONE") # PHONE, GOOGLE
    is_registered_on_chain = Column(Boolean, default=False)
    
    wallet = relationship("Wallet", back_populates="owner", uselist=False)
    vaults = relationship("Vault", back_populates="owner")
    rules = relationship("ProgrammableRule", back_populates="user")
    transactions_sent = relationship("TransactionHistory", foreign_keys="[TransactionHistory.sender_id]", back_populates="sender")
    transactions_received = relationship("TransactionHistory", foreign_keys="[TransactionHistory.receiver_id]", back_populates="receiver")

class Wallet(Base):
    __tablename__ = "wallets"

    id = Column(Integer, primary_key=True, index=True)
    address = Column(String, unique=True, index=True)
    encrypted_keypair = Column(String) # For MVP abstraction. In prod, this should be KMS or secure enclave.
    owner_id = Column(Integer, ForeignKey("users.id"))

    owner = relationship("User", back_populates="wallet")

class Vault(Base):
    __tablename__ = "vaults"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String) # e.g. "Savings", "Emergency"
    object_id = Column(String, unique=True) # On-chain shared Vault object ID
    vault_cap_id = Column(String, nullable=True) # On-chain VaultCap (owned) object ID
    owner_id = Column(Integer, ForeignKey("users.id"))
    
    owner = relationship("User", back_populates="vaults")

class TransactionHistory(Base):
    __tablename__ = "transaction_history"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(Float)
    status = Column(String) # "PENDING", "COMPLETED", "FAILED"
    sui_digest = Column(String, nullable=True) # Blockchain txn hash
    timestamp = Column(DateTime, default=datetime.utcnow)
    is_programmable = Column(Boolean, default=False)
    
    # Sponsored Transaction Pipeline Fields
    intent_id = Column(String, unique=True, index=True, nullable=True)
    tx_bytes = Column(String, nullable=True)
    sponsor_signature = Column(String, nullable=True)
    user_signature = Column(String, nullable=True)
    gas_budget = Column(Integer, nullable=True)
    split_rules = Column(String, nullable=True) # Serialized JSON string of flow config
    
    sender = relationship("User", foreign_keys=[sender_id], back_populates="transactions_sent")
    receiver = relationship("User", foreign_keys=[receiver_id], back_populates="transactions_received")

class QueuedTransaction(Base):
    __tablename__ = "queued_transactions"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_phone = Column(String)
    amount = Column(Float)
    timestamp = Column(DateTime, default=datetime.utcnow)
    status = Column(String, default="QUEUED") # QUEUED, PROCESSING, FAILED
    retry_count = Column(Integer, default=0)

class ProgrammableRule(Base):
    __tablename__ = "programmable_rules"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    rule_type = Column(String) # e.g. "salary_split", "auto_save"
    target_vault_id = Column(Integer, ForeignKey("vaults.id"), nullable=True)
    percentage = Column(Float) # e.g. 15.0 for 15%
    is_active = Column(Boolean, default=True)

    user = relationship("User", back_populates="rules")
    target_vault = relationship("Vault")
