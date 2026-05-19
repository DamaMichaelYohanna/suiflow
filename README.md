# SuiFlow: Programmable Payments MVP

SuiFlow is an offline-first programmable payment platform built on Sui. It allows users to send money via phone numbers and setup programmable flows like auto-saving using Programmable Transaction Blocks (PTBs).

## Architecture

*   **Mobile App (Flutter):** Located in `suiver/`. Uses Hive for offline-first transaction queuing. Designed with a modern, premium material theme.
*   **Backend (FastAPI):** Located in `backend/`. Handles wallet abstraction, authentication, and offline queue synchronization. Connects to PostgreSQL and interacts with the Sui Blockchain.
*   **Smart Contracts (Sui Move):** Located in `contracts/`. Contains modular contracts for Wallet Registry, Payments, Vaults, and Programmable Flows.

## Setup Instructions

### 1. Backend (FastAPI)
```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL="postgresql://user:password@localhost/suiflow"
uvicorn main:app --reload
```

### 2. Mobile App (Flutter)
```bash
cd suiver
flutter pub get
flutter run
```

### 3. Smart Contracts (Sui Move)
```bash
cd contracts
sui move build
sui client publish --gas-budget 100000000
```

## Demo Flow

1.  **Onboarding:** Open the Flutter app, enter a phone number to "Login". The backend automatically abstracts wallet creation.
2.  **Dashboard:** View your mock balance and vaults.
3.  **Offline Payment:** Turn off internet on the emulator/device.
4.  **Send Payment:** Go to "Send", enter a recipient, amount, and set a Programmable Split (e.g., 20% to savings).
5.  **Queue:** The transaction is queued in the local Hive box.
6.  **Sync:** Turn internet back on. The app will sync the queue to the backend.
7.  **PTB Execution:** The backend receives the batch, builds the PTB executing the transfer and the split to the vault, and submits it to the Sui network.
