#[starknet::interface]
pub trait ICounter<TContractState> {
    fn get_counter(self: @TContractState) -> u32; // view function - doesn't modify the state - no gas costs, etc
    fn increase_counter(ref self: TContractState); // mutate the state - gas costs, etc
    fn decrease_counter(ref self: TContractState); 
    fn reset_counter(ref self: TContractState); // mutate the state - gas costs, etc
}

#[starknet::contract]
pub mod Counter {
    use OwnableComponent::InternalTrait;
    
    use super::ICounter;
    use openzeppelin_access::ownable::OwnableComponent;
    use starknet::{ContractAddress, get_caller_address};

    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
   
    component!(path: OwnableComponent, storage: ownable, event:OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableTwoStepImpl = OwnableComponent::OwnableTwoStepImpl<ContractState>;


    #[storage]
    pub struct Storage {
        counter: u32,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    // Here the constructor is initialized with a default value of 0
    // #[constructor] 
    // fn constructor(ref self: ContractState, owner: ContractAddress) {
    //    self.counter.write(0);
    //    self.ownable.initializer(owner);
    // }

    // In order to use this method we need to update deploy.ts to accept an init_value
    // deploy.ts:
        // contract: "Counter",
        //      constructorArgs: {
        //      owner: deployer.address,
        //      init_value: 0,
        // },

    #[constructor] 
    fn constructor(ref self: ContractState, init_value: u32, owner: ContractAddress) {
       self.counter.write(init_value);
       self.ownable.initializer(owner);
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Increased: Increased,
        Decreased: Decreased,

        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    pub struct Increased {
        pub account:ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    pub struct Decreased {
        pub account:ContractAddress
    }

    pub mod Error {
        pub const EMPTY_COUNTER: felt252 = 'Decreasing Empty counter';
    }

    #[abi(embed_v0)] 
    impl CounterImpl of ICounter<ContractState> {
        fn get_counter(self: @ContractState) -> u32 {
            self.counter.read()
        }

        fn increase_counter(ref self: ContractState) {
            let new_value = self.counter.read() + 1;
            self.counter.write(new_value);
            self.emit(Increased {account: get_caller_address()});
        }

        fn decrease_counter(ref self: ContractState) {
            let old_value = self.counter.read();
            assert(old_value > 0, Error::EMPTY_COUNTER);
            self.counter.write(old_value - 1);
            self.emit(Decreased {account: get_caller_address()});
        }

        fn reset_counter(ref self: ContractState) {
            // only owner can reset
            self.ownable.assert_only_owner();
            self.counter.write(0);
        }
    }
}

