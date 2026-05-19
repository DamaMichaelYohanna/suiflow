module suiflow::payment {
    use sui::object::{Self, UID};
    use sui::coin::{Self, Coin};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::vec_set::{Self, VecSet};
    use std::type_name;
    use sui::event;
    use std::string::String;
    use std::ascii::String as AsciiString;
    use suiflow::wallet_registry::{Registry, AdminCap, get_wallet_address};

    // --- Error Codes ---
    const EIntentAlreadyProcessed: u64 = 700;
    const EAssetNotWhitelisted: u64 = 701;

    /// Shared object tracking processed transaction intent IDs to prevent replay attacks in offline queues.
    public struct PaymentStore has key {
        id: UID,
        processed_intents: Table<String, bool>,
    }

    /// Shared object holding whitelisted asset type names allowed for payments.
    public struct AssetWhitelist has key {
        id: UID,
        allowed_types: VecSet<AsciiString>,
    }

    /// Event emitted when a payment is successfully sent
    public struct PaymentSent has copy, drop {
        intent_id: String,
        recipient: address,
        amount: u64,
    }

    fun init(ctx: &mut TxContext) {
        let store = PaymentStore {
            id: object::new(ctx),
            processed_intents: table::new(ctx),
        };
        transfer::share_object(store);

        let whitelist = AssetWhitelist {
            id: object::new(ctx),
            allowed_types: vec_set::empty(),
        };
        transfer::share_object(whitelist);
    }

    /// Admin function to add a whitelisted asset type
    public fun add_asset<T>(_admin: &AdminCap, whitelist: &mut AssetWhitelist) {
        let type_name = type_name::into_string(type_name::with_defining_ids<T>());
        if (!vec_set::contains(&whitelist.allowed_types, &type_name)) {
            vec_set::insert(&mut whitelist.allowed_types, type_name);
        };
    }

    /// Admin function to remove a whitelisted asset type
    public fun remove_asset<T>(_admin: &AdminCap, whitelist: &mut AssetWhitelist) {
        let type_name = type_name::into_string(type_name::with_defining_ids<T>());
        if (vec_set::contains(&whitelist.allowed_types, &type_name)) {
            vec_set::remove(&mut whitelist.allowed_types, &type_name);
        };
    }

    /// Helper to assert an asset is whitelisted
    public fun assert_whitelisted<T>(whitelist: &AssetWhitelist) {
        let type_name = type_name::into_string(type_name::with_defining_ids<T>());
        assert!(vec_set::contains(&whitelist.allowed_types, &type_name), EAssetNotWhitelisted);
    }

    /// Send a specific coin directly to a user's phone number with replay protection and asset whitelisting.
    public fun send_payment<T>(
        whitelist: &AssetWhitelist,
        store: &mut PaymentStore,
        registry: &Registry,
        intent_id: String,
        phone_number: vector<u8>,
        coin: Coin<T>,
        _ctx: &mut TxContext
    ) {
        assert_whitelisted<T>(whitelist);
        assert!(!table::contains(&store.processed_intents, intent_id), EIntentAlreadyProcessed);
        table::add(&mut store.processed_intents, intent_id, true);

        let amount = coin::value(&coin);
        let recipient_address = get_wallet_address(registry, phone_number);
        transfer::public_transfer(coin, recipient_address);

        event::emit(PaymentSent {
            intent_id,
            recipient: recipient_address,
            amount,
        });
    }

    /// Utility function used in Programmable Transaction Blocks (PTBs)
    /// Allows taking a portion of a coin and returning the remainder for other operations.
    public fun split_and_transfer<T>(
        coin: &mut Coin<T>,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        let split_coin = coin::split(coin, amount, ctx);
        transfer::public_transfer(split_coin, recipient);
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }
}
