import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

load_dotenv()

# The user will provide this in their environment; fallback to SQLite safely on Vercel or local
SQLALCHEMY_DATABASE_URL = os.getenv("DATABASE_URL")
if not SQLALCHEMY_DATABASE_URL:
    if os.environ.get("VERCEL") == "1":
        SQLALCHEMY_DATABASE_URL = "sqlite:////tmp/sql_app.db"
    else:
        SQLALCHEMY_DATABASE_URL = "sqlite:///./sql_app.db"
elif SQLALCHEMY_DATABASE_URL.startswith("sqlite:///./") and os.environ.get("VERCEL") == "1":
    SQLALCHEMY_DATABASE_URL = "sqlite:////tmp/" + SQLALCHEMY_DATABASE_URL.split("sqlite:///./")[-1]

# For SQLite, we need connect_args={"check_same_thread": False}
if SQLALCHEMY_DATABASE_URL.startswith("sqlite"):
    engine = create_engine(SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False})
else:
    engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def run_migrations(engine):
    from sqlalchemy import text
    # Run column migrations to ensure older database schemas are upgraded
    with engine.connect() as conn:
        # Columns to ensure in 'users' table
        user_columns = [
            ("hashed_password", "VARCHAR"),
            ("social_id", "VARCHAR"),
            ("auth_method", "VARCHAR")
        ]
        for col_name, col_type in user_columns:
            try:
                conn.execute(text(f"ALTER TABLE users ADD COLUMN {col_name} {col_type}"))
                conn.commit()
                print(f"[MIGRATION] Added column users.{col_name}")
            except Exception:
                pass

        # Columns to ensure in 'transaction_history' table
        tx_columns = [
            ("intent_id", "VARCHAR"),
            ("tx_bytes", "VARCHAR"),
            ("sponsor_signature", "VARCHAR"),
            ("user_signature", "VARCHAR"),
            ("gas_budget", "INTEGER"),
            ("split_rules", "VARCHAR")
        ]
        for col_name, col_type in tx_columns:
            try:
                conn.execute(text(f"ALTER TABLE transaction_history ADD COLUMN {col_name} {col_type}"))
                conn.commit()
                print(f"[MIGRATION] Added column transaction_history.{col_name}")
            except Exception:
                pass

