module suiflow::programmable_flows {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use std::string::String;
    use std::vector;
    use suiflow::vaults::{Vault, deposit_for_ptb};

    // --- Error Codes ---
    const EInvalidPercentage: u64 = 500;
    const EInvalidTotalPercentage: u64 = 501;

    /// Event emitted when a split payment is executed
    public struct PaymentSplitExecuted has copy, drop {
        total_amount: u64,
        savings_amount: u64,
        spending_amount: u64,
        recipient: address,
    }

    /// Event emitted when a FlowConfig is created or updated
    public struct FlowConfigCreated has copy, drop {
        config_id: sui::object::ID,
        owner: address,
    }

    /// Represents a single routing rule inside a FlowConfig
    public struct RouteRule has store, copy, drop {
        name: String,        // E.g., "savings", "rent", "wallet"
        percentage: u64,     // Out of 100
        recipient: address,  // Wallet address or Vault object ID address
        is_vault: bool,      // True if destination is a Vault
    }

    /// On-chain user configuration object storing dynamic routing rules for automated PTB composition.
    public struct FlowConfig has key {
        id: UID,
        owner: address,
        rules: vector<RouteRule>,
    }

    /// Create a new RouteRule struct
    public fun create_route_rule(
        name: String,
        percentage: u64,
        recipient: address,
        is_vault: bool,
    ): RouteRule {
        RouteRule {
            name,
            percentage,
            recipient,
            is_vault,
        }
    }

    /// Create a new dynamic FlowConfig object storing user routing preferences
    public fun create_flow_config(rules: vector<RouteRule>, ctx: &mut TxContext) {
        // Validate total percentage does not exceed 100%
        let mut total_pct = 0;
        let mut i = 0;
        let len = vector::length(&rules);
        while (i < len) {
            let rule = vector::borrow(&rules, i);
            total_pct = total_pct + rule.percentage;
            i = i + 1;
        };
        assert!(total_pct <= 100, EInvalidTotalPercentage);

        let config_uid = object::new(ctx);
        let config_id = object::uid_to_inner(&config_uid);
        let owner = tx_context::sender(ctx);

        let config = FlowConfig {
            id: config_uid,
            owner,
            rules,
        };

        event::emit(FlowConfigCreated {
            config_id,
            owner,
        });

        transfer::transfer(config, owner);
    }

    /// Fixed and optimized automated routing logic for a simple 2-way split
    public fun split_to_vault_and_wallet<T>(
        payment: Coin<T>,             // Take full ownership to distribute accurately
        vault: &mut Vault<T>,
        savings_percentage: u64,      // out of 100
        recipient_wallet: address,
        ctx: &mut TxContext
    ) {
        assert!(savings_percentage <= 100, EInvalidPercentage);
        
        let mut payment = payment; // Make mutable to split it
        let total_amount = coin::value(&payment);
        let savings_amount = (total_amount * savings_percentage) / 100;
        let spending_amount = total_amount - savings_amount;

        // 1. Isolate savings portion and deposit
        if (savings_amount > 0) {
            let savings_coin = coin::split(&mut payment, savings_amount, ctx);
            deposit_for_ptb(vault, savings_coin, ctx);
        };

        // 2. The remainder of the coin IS the spending amount. 
        // No extra split needed. Simply transfer the remaining object.
        transfer::public_transfer(payment, recipient_wallet);

        event::emit(PaymentSplitExecuted {
            total_amount,
            savings_amount,
            spending_amount,
            recipient: recipient_wallet,
        });
    }
}
