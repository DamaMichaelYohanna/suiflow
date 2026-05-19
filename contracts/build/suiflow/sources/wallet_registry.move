module suiflow::wallet_registry {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use std::string::String;
    use sui::event;

    // --- Error Codes ---
    const EPhoneAlreadyRegistered: u64 = 600;
    const EPhoneNotFound: u64 = 601;

    /// Capability granting admin permission to register users (e.g. backend oracle)
    public struct AdminCap has key, store {
        id: UID,
    }

    /// A record of a registered user.
    public struct UserRecord has store, copy, drop {
        wallet: address,
        display_name: String,
    }

    /// The central registry mapping phone numbers (normalized off-chain as byte vectors) to their registered user records.
    public struct Registry has key {
        id: UID,
        user_map: Table<vector<u8>, UserRecord>,
    }

    /// Event emitted when a new user registers
    public struct UserRegistered has copy, drop {
        phone_number: vector<u8>,
        display_name: String,
        wallet: address,
    }

    fun init(ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            user_map: table::new(ctx),
        };
        transfer::share_object(registry);

        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::public_transfer(admin_cap, tx_context::sender(ctx));
    }

    /// Register a new user in the registry. Protected by AdminCap.
    public fun register_user(
        _admin: &AdminCap,
        registry: &mut Registry, 
        phone_number: vector<u8>, 
        display_name: String,
        wallet: address, 
        _ctx: &mut TxContext
    ) {
        assert!(!table::contains(&registry.user_map, phone_number), EPhoneAlreadyRegistered);
        
        let record = UserRecord {
            wallet,
            display_name,
        };
        
        table::add(&mut registry.user_map, phone_number, record);
        
        event::emit(UserRegistered {
            phone_number,
            display_name,
            wallet,
        });
    }

    /// Retrieves the wallet address associated with a phone number.
    public fun get_wallet_address(registry: &Registry, phone_number: vector<u8>): address {
        assert!(table::contains(&registry.user_map, phone_number), EPhoneNotFound);
        table::borrow(&registry.user_map, phone_number).wallet
    }

    /// Retrieves the display name associated with a phone number.
    public fun get_display_name(registry: &Registry, phone_number: vector<u8>): String {
        assert!(table::contains(&registry.user_map, phone_number), EPhoneNotFound);
        table::borrow(&registry.user_map, phone_number).display_name
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}
