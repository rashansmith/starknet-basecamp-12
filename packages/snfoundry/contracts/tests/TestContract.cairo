use snforge_std::EventSpyAssertionsTrait;
// import library
use snforge_std::{declare, DeclareResultTrait, 
    ContractClassTrait, spy_events, start_cheat_caller_address, stop_cheat_caller_address};
use contracts::counter::{ Counter, ICounterSafeDispatcher, ICounterSafeDispatcherTrait};
    use starknet::{ContractAddress};
use contracts::counter::{ICounterDispatcher, ICounterDispatcherTrait};
use openzeppelin_access::ownable::interface::{ IOwnableDispatcher, IOwnableDispatcherTrait};

const ZERO_COUNT: u32 = 0;
// Test Accounts
fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

// util deploy function
fn __deploy__(init_value: u32) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher) {
    // declare
    let contract_class = declare("Counter").unwrap().contract_class();

    // serialize constructor
    let mut calldata: Array<felt252> = array![];
    init_value.serialize(ref calldata); // convert zero count to felt252
    OWNER().serialize(ref calldata);

    // deploy contract
    let (contract_address, _) = contract_class.deploy(@calldata).expect('failed to deploy contract');

    let counter = ICounterDispatcher {contract_address}; 
    let ownable = IOwnableDispatcher {contract_address};
    let safe_dispatcher = ICounterSafeDispatcher {contract_address};
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
    // assert(count_2 == count_1 + 5, 'invalid count'); - should fail
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
            Counter::Event::Increased(Counter::Increased {account: USER_1()})
        )
    ]);

    spy.assert_not_emitted(@array![
        (
            counter.contract_address,
            Counter::Event::Decreased(Counter::Decreased {account: USER_1()})
        )
    ]);
}

#[ignore]
#[test]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter() {
    let (counter, _, safe_dispatcher) = __deploy__(ZERO_COUNT);
  
    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.decrease_counter();
    stop_cheat_caller_address(counter.contract_address);
    match safe_dispatcher.decrease_counter() {
        Result::Ok(_) => panic!("cannot decrease to 0"),
        Result::Err(e) => assert(*e[0] == 'Decreasing empty counter', *e.at(0))
    }
    
}

#[ignore]
#[test]
#[should_panic(expected: 'cannot decrease to 0')]
fn test_panic_decrease_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
  
    assert(counter.get_counter() == ZERO_COUNT, 'cannot decrease to 0');

    counter.decrease_counter();
}

#[test]
fn test_successful_decrease_counter() {
    let (counter, _, _) = __deploy__(5);

    let count_1 = counter.get_counter();

    assert(count_1 == 5, 'invalid count');

    // execute decrease_counter txn
    counter.decrease_counter();
    let final_count = counter.get_counter();
    assert(final_count == count_1 - 1, 'invalid count');
}

#[ignore]
#[test]
#[feature("safe_dispatcher")]
fn test_safe_panic_reset_counter_by_non_owner() {
    let (counter, _, safe_dispatcher) = __deploy__(ZERO_COUNT);
  
    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    match safe_dispatcher.reset_counter() {
        Result::Ok(_) => panic!("cannot reset"),
        Result::Err(e) => assert(*e[0] == 'Caller is not owner', *e.at(0))
    }  

    stop_cheat_caller_address(counter.contract_address);
 
}


#[test]
fn test_successful_reset_counter() {
    let (counter, _, _) = __deploy__(5);

    let count_1 = counter.get_counter();

    assert(count_1 == 5, 'invalid count');

    // simulate as owner
    start_cheat_caller_address(counter.contract_address, OWNER());

    // execute decrease_counter txn
    counter.reset_counter();
    let final_count = counter.get_counter();
    assert(final_count == 0, 'invalid count');

    stop_cheat_caller_address(counter.contract_address);
}




