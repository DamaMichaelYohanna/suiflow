#[test_only]
module suiflow::suiflow_tests {
    use sui::test_scenario::{Self, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string::{Self};
    use std::vector;
    use suiflow::wallet_registry::{Self, Registry, AdminCap};
    use suiflow::vaults::{Self, Vault, VaultCap};
    use suiflow::payment::{Self, PaymentStore, AssetWhitelist};
    use suiflow::programmable_flows::{Self, FlowConfig, RouteRule};
    use suiflow::transaction_receipts::{Self, Receipt};

    #[test]
    fun test_full_suiflow_lifecycle() {
        let admin = @0xAD;
        let user1 = @0x11;

        let mut scenario_val = test_scenario::begin(admin);
        let scenario = &mut scenario_val;

        // 1. Admin initializes Registry and Payment modules
        test_scenario::next_tx(scenario, admin);
        {
            wallet_registry::test_init(test_scenario::ctx(scenario));
            payment::test_init(test_scenario::ctx(scenario));
        };

        // 2. Admin configures AssetWhitelist and registers User1
        test_scenario::next_tx(scenario, admin);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let mut whitelist = test_scenario::take_shared<AssetWhitelist>(scenario);
            let mut registry = test_scenario::take_shared<Registry>(scenario);

            // Whitelist SUI coin
            payment::add_asset<SUI>(&admin_cap, &mut whitelist);

            // Register User1 with normalized phone number b"+1234567890"
            wallet_registry::register_user(
                &admin_cap,
                &mut registry,
                b"+1234567890",
                string::utf8(b"Alice"),
                user1,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, admin_cap);
            test_scenario::return_shared(whitelist);
            test_scenario::return_shared(registry);
        };

        // 3. User1 creates a Vault and FlowConfig
        test_scenario::next_tx(scenario, user1);
        {
            vaults::create_vault<SUI>(test_scenario::ctx(scenario));

            // Create FlowConfig rules
            let rule1 = programmable_flows::create_route_rule(
                string::utf8(b"savings"),
                30,
                user1, // Placeholder, in real usage vault ID or wallet
                true,
            );
            let rule2 = programmable_flows::create_route_rule(
                string::utf8(b"wallet"),
                70,
                user1,
                false,
            );

            let rules = vector[rule1, rule2];

            programmable_flows::create_flow_config(rules, test_scenario::ctx(scenario));
        };

        // 4. Admin/Relayer sends payment to User1 using phone number
        test_scenario::next_tx(scenario, admin);
        {
            let whitelist = test_scenario::take_shared<AssetWhitelist>(scenario);
            let mut store = test_scenario::take_shared<PaymentStore>(scenario);
            let registry = test_scenario::take_shared<Registry>(scenario);

            let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));

            payment::send_payment<SUI>(
                &whitelist,
                &mut store,
                &registry,
                string::utf8(b"intent_123"),
                b"+1234567890",
                coin,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(whitelist);
            test_scenario::return_shared(store);
            test_scenario::return_shared(registry);
        };

        // 5. User1 executes split_to_vault_and_wallet and generates receipt
        test_scenario::next_tx(scenario, user1);
        {
            let mut vault = test_scenario::take_shared<Vault<SUI>>(scenario);
            let payment_coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));

            programmable_flows::split_to_vault_and_wallet<SUI>(
                payment_coin,
                &mut vault,
                30,
                user1,
                test_scenario::ctx(scenario)
            );

            transaction_receipts::generate_receipt(
                string::utf8(b"Salary Split"),
                1000,
                user1,
                700,
                300,
                1670000000000,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(vault);
        };

        // 6. User1 withdraws from Vault using VaultCap
        test_scenario::next_tx(scenario, user1);
        {
            let vault_cap = test_scenario::take_from_sender<VaultCap>(scenario);
            let mut vault = test_scenario::take_shared<Vault<SUI>>(scenario);

            vaults::withdraw<SUI>(
                &vault_cap,
                &mut vault,
                300,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, vault_cap);
            test_scenario::return_shared(vault);
        };

        test_scenario::end(scenario_val);
    }
}
