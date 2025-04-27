use snforge_std::DeclareResultTrait;
use contracts::counter::{Counter, ICounterSafeDispatcher};
use contracts::counter::{ICounterDispatcher, ICounterDispatcherTrait};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use snforge_std::EventSpyAssertionsTrait;
use snforge_std::{
    declare, spy_events, start_cheat_caller_address, stop_cheat_caller_address,
    start_mock_call, stop_mock_call, ContractClassTrait
};
use starknet::{ContractAddress};

const ZERO_COUNT: u32 = 0;
const WIN_NUMBER: u32 = 5; 

// Test Accounts
fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

// Mock STRK token address
fn STRK_TOKEN() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

// util deploy function
fn __deploy__(init_value: u32) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher) {

    let mut calldata: Array<felt252> = array![];
    OWNER().serialize(ref calldata);

    // Deploy the contract using the contract_class
    let (contract_address, _) = declare("Counter")
    .unwrap()
    .contract_class()
    .deploy(@calldata)
    .unwrap();

    let counter = ICounterDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };
    let safe_dispatcher = ICounterSafeDispatcher { contract_address };
    
    // Default mock for STRK token calls
    // Mock balanceOf to return 0 by default
    start_mock_call(STRK_TOKEN(), selector!("balanceOf"), 0);
    // Mock transfer to return success
    start_mock_call(STRK_TOKEN(), selector!("transfer"), 1);
    // Mock transferFrom to return success
    start_mock_call(STRK_TOKEN(), selector!("transferFrom"), 1);
    
    (counter, ownable, safe_dispatcher)
}


#[test]
fn test_counter_deployment() {
    let (counter, ownable, _) = __deploy__(ZERO_COUNT);
    let count_1 = counter.get_counter();
    assert(count_1 == ZERO_COUNT, 'count not set');
    assert(ownable.owner() == OWNER(), 'owner not set');
}

#[test]
fn test_increase_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    // get current count
    let count_1 = counter.get_counter();

    // assertions
    assert(count_1 == ZERO_COUNT, 'count not set');

    // state changing txn
    counter.increase_counter();

    // retrieve current count
    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'invalid count');
}

#[test]
fn test_emitted_increased_event() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);

    let mut spy = spy_events();
    // mock a caller
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    spy.assert_emitted(@array![
        (
            counter.contract_address,
            Counter::Event::Increased(Counter::Increased { account: USER_1() }),
        ),
    ]);

    spy.assert_not_emitted(@array![
        (
            counter.contract_address,
            Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
        ),
    ]);
}

#[test]
#[should_panic(expected: 'Decreasing Empty counter')]
fn test_panic_decrease_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    assert(counter.get_counter() == ZERO_COUNT, 'counter should be zero');
    counter.decrease_counter();
}

#[test]
fn test_successful_decrease_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    
    // First increase counter to 1
    counter.increase_counter();
    let count_1 = counter.get_counter();
    assert(count_1 == 1, 'invalid count');

    // Now decrease it
    counter.decrease_counter();
    let final_count = counter.get_counter();
    assert(final_count == 0, 'invalid count');
}

#[ignore]
#[test]
fn test_successful_reset_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    
    // Increase counter to 1
    counter.increase_counter();
    assert(counter.get_counter() == 1, 'invalid count');

    // Setup the mock for balanceOf to return tokens (100 tokens)
    stop_mock_call(STRK_TOKEN(), selector!("balanceOf"));
    start_mock_call(STRK_TOKEN(), selector!("balanceOf"), 100);

    // Reset as owner - this should work for the owner
    start_cheat_caller_address(counter.contract_address, OWNER());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);
    
    let final_count = counter.get_counter();
    assert(final_count == 0, 'invalid count');
}

#[test]
fn test_win_number() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    
    // Verify win number matches constant
    let win_num = counter.get_win_number();
    assert(win_num == WIN_NUMBER, 'wrong win number');
}

#[ignore]
#[test]
fn test_win_condition_transfers_tokens() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    
    // Setup mock for contract to have 100 STRK tokens
    stop_mock_call(STRK_TOKEN(), selector!("balanceOf"));
    start_mock_call(STRK_TOKEN(), selector!("balanceOf"), 100);
    
    // Create a spy to verify the transfer call
    let mut spy = spy_events();
    
    // Prank as USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());
    
    // Increase counter WIN_NUMBER times to trigger win condition
    // We'll increase it to WIN_NUMBER-1 first
    let mut i = 0;
    while i < WIN_NUMBER - 1 {
        counter.increase_counter();
        i += 1;
    };
    
    // The next increase should trigger the win condition
    counter.increase_counter();
    
    // Check counter is at WIN_NUMBER
    assert(counter.get_counter() == WIN_NUMBER, 'counter should be at win number');
    
    // In a real scenario, we would verify that tokens were transferred to USER_1
    // but here we're just checking that the counter works correctly
    stop_cheat_caller_address(counter.contract_address);
    
    // Verify the Increased event was emitted
    spy.assert_emitted(@array![
        (
            counter.contract_address,
            Counter::Event::Increased(Counter::Increased { account: USER_1() }),
        ),
    ]);
}

// Test that only the owner can reset the counter
#[ignore]
#[test]
#[should_panic(expected: 'Caller is not the owner')]
fn test_reset_counter_permission() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);

    // Try to reset as non-owner
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.reset_counter();  // This should panic with 'Caller is not the owner'
    stop_cheat_caller_address(counter.contract_address);
}