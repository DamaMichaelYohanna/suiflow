module suiflow::vaults {
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::event;

    // --- Error Codes ---
    const EInvalidVaultCap: u64 = 402;

    /// Capability required to withdraw funds from a specific vault
    public struct VaultCap has key, store {
        id: UID,
        vault_id: ID,
    }

    /// Represents a smart vault owned by a user (e.g. Savings, Emergency)
    public struct Vault<phantom T> has key {
        id: UID,
        balance: Balance<T>,
        owner: address,
    }

    /// Event emitted when funds are deposited into a vault
    public struct VaultDeposit has copy, drop {
        vault_id: ID,
        amount: u64,
    }

    /// Event emitted when funds are withdrawn from a vault
    public struct VaultWithdraw has copy, drop {
        vault_id: ID,
        amount: u64,
    }

    /// Create a new Vault and its corresponding VaultCap
    #[allow(lint(self_transfer))]
    public fun create_vault<T>(ctx: &mut TxContext) {
        let vault_uid = object::new(ctx);
        let vault_id = object::uid_to_inner(&vault_uid);
        
        let vault = Vault<T> {
            id: vault_uid,
            balance: balance::zero<T>(),
            owner: tx_context::sender(ctx),
        };
        transfer::share_object(vault);

        let vault_cap = VaultCap {
            id: object::new(ctx),
            vault_id,
        };
        transfer::public_transfer(vault_cap, tx_context::sender(ctx));
    }

    /// Deposit funds into a vault
    public fun deposit<T>(
        vault: &mut Vault<T>,
        payment: Coin<T>,
        _ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        let balance = coin::into_balance(payment);
        balance::join(&mut vault.balance, balance);

        event::emit(VaultDeposit {
            vault_id: object::id(vault),
            amount,
        });
    }

    /// Withdraw funds from a vault using VaultCap
    #[allow(lint(self_transfer))]
    public fun withdraw<T>(
        cap: &VaultCap,
        vault: &mut Vault<T>,
        amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(cap.vault_id == object::id(vault), EInvalidVaultCap);
        let withdraw_balance = balance::split(&mut vault.balance, amount);
        let coin = coin::from_balance(withdraw_balance, ctx);
        transfer::public_transfer(coin, tx_context::sender(ctx));

        event::emit(VaultWithdraw {
            vault_id: object::id(vault),
            amount,
        });
    }
    
    /// Deposit funds into a vault, intended to be used in PTBs
    public fun deposit_for_ptb<T>(
        vault: &mut Vault<T>,
        payment: Coin<T>,
        _ctx: &mut TxContext
    ) {
        let amount = coin::value(&payment);
        let balance = coin::into_balance(payment);
        balance::join(&mut vault.balance, balance);

        event::emit(VaultDeposit {
            vault_id: object::id(vault),
            amount,
        });
    }
}
