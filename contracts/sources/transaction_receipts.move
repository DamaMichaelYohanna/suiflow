module suiflow::transaction_receipts {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use std::string::String;

    // --- Error Codes ---

    /// Structured breakdown of the programmable financial flow
    public struct FlowBreakdown has store, copy, drop {
        spending_amount: u64,
        savings_amount: u64,
    }

    /// Stores metadata about a completed programmable flow for history and tracking.
    /// Strictly non-copyable primitive acting as a unique legal/financial certification.
    public struct Receipt has key, store {
        id: UID,
        transaction_type: String,
        amount: u64,
        recipient: address,
        breakdown: FlowBreakdown,
        timestamp_ms: u64,
    }

    /// Emitted when a receipt is created
    public struct ReceiptCreated has copy, drop {
        receipt_id: sui::object::ID,
        transaction_type: String,
        amount: u64,
        recipient: address,
        timestamp_ms: u64,
    }

    /// Create and transfer a receipt directly to the intended recipient
    public fun generate_receipt(
        transaction_type: String,
        amount: u64,
        recipient: address,
        spending_amount: u64,
        savings_amount: u64,
        timestamp_ms: u64,
        ctx: &mut TxContext
    ) {
        let breakdown = FlowBreakdown {
            spending_amount,
            savings_amount,
        };

        let receipt = Receipt {
            id: object::new(ctx),
            transaction_type,
            amount,
            recipient,
            breakdown,
            timestamp_ms,
        };

        event::emit(ReceiptCreated {
            receipt_id: object::id(&receipt),
            transaction_type,
            amount,
            recipient,
            timestamp_ms,
        });

        transfer::public_transfer(receipt, recipient);
    }
}
