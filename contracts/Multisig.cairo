# A Cairo multisig, using the following reference implementation:
# https://solidity-by-example.org/app/multi-sig-wallet/

%lang starknet

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.math import assert_le, assert_lt
from starkware.starknet.common.syscalls import call_contract, get_caller_address

from contracts.utils.constants import FALSE, TRUE


#
# Events
#

@event
func SubmitTransaction(owner : felt, tx_index : felt, to : felt):
end

@event
func ConfirmTransaction(owner : felt, tx_index : felt):
end

@event
func RevokeConfirmation(owner : felt, tx_index : felt):
end

@event
func ExecuteTransaction(owner : felt, tx_index : felt):
end

#
# Storage
#

struct Transaction:
    member to : felt
    member function_selector : felt
    member calldata_len : felt
    member executed : felt
    member num_confirmations : felt
end

@storage_var
func _confirmations_required() -> (res : felt):
end

@storage_var
func _owners_len() -> (res : felt):
end

@storage_var
func _owners(index : felt) -> (res : felt):
end

@storage_var
func _is_owner(address : felt) -> (res : felt):
end

@storage_var
func _next_tx_index() -> (res : felt):
end

@storage_var
func _transactions(tx_index : felt, field : felt) -> (res : felt):
# Field enum pattern described in https://hackmd.io/@RoboTeddy/BJZFu56wF#Concise-way
end

@storage_var
func _transaction_calldata(tx_index : felt, calldata_index : felt) -> (res : felt):
end

@storage_var
func _is_confirmed(tx_index : felt, owner : felt) -> (res : felt):
end

#
# Conditions
#

# Revert if the calling account is not an owner
func require_owner{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }():
    let (caller) = get_caller_address()
    let (is_caller_owner) = is_owner(address=caller)
    with_attr error_message("not owner"):
        assert is_caller_owner = TRUE
    end
    return ()
end

# Revert if tx does not exist
func require_tx_exists{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    let (next_tx_index) = _next_tx_index.read()
    with_attr error_message("tx does not exist"):
        assert_lt(tx_index, next_tx_index)
    end
    return ()
end

# Revert if tx has been executed
func require_not_executed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    let (is_executed) = _transactions.read(tx_index=tx_index, field=Transaction.executed)
    with_attr error_message("tx already executed"):
        assert is_executed = FALSE
    end
    return ()
end

# Revert if tx has been confirmed for the calling account already
func require_not_confirmed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    let (caller) = get_caller_address()
    let (is_confirmed_for_caller) = is_confirmed(tx_index=tx_index, owner=caller)
    with_attr error_message("tx already confirmed"):
        assert is_confirmed_for_caller = FALSE
    end
    return ()
end

# Revert if tx has not been confirmed for the calling account already
func require_confirmed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    let (caller) = get_caller_address()
    let (is_confirmed_for_caller) = is_confirmed(tx_index=tx_index, owner=caller)
    with_attr error_message("tx not confirmed"):
        assert is_confirmed_for_caller = TRUE
    end
    return ()
end


#
# Getters
#

@view
func is_owner{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address : felt) -> (res : felt):
    let (res) = _is_owner.read(address=address)
    return (res)
end

@view
func get_owners_len{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (owners_len : felt):
    let (owners_len) = _owners_len.read()
    return (owners_len=owners_len)
end

@view
func _get_owners{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        owners_index : felt,
        owners_len : felt,
        owners : felt*,
    ):
    if owners_index == owners_len:
        return ()
    end

    let (owner) = _owners.read(index=owners_index)
    assert owners[owners_index] = owner

    _get_owners(owners_index=owners_index + 1, owners_len=owners_len, owners=owners)
    return ()
end

@view
func get_owners{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (
        owners_len : felt,
        owners : felt*,
    ):
    alloc_locals
    let (owners) = alloc()
    let (owners_len) = _owners_len.read()
    if owners_len == 0:
        return (owners_len=owners_len, owners=owners)
    end

    # Recursively add owners from storage to the owners array
    _get_owners(owners_index=0, owners_len=owners_len, owners=owners)
    return (owners_len=owners_len, owners=owners)
end

@view
func get_transactions_len{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (res : felt):
    let (res) = _next_tx_index.read()
    return (res)
end

@view
func get_confirmations_required{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (confirmations_required : felt):
    let (confirmations_required) = _confirmations_required.read()
    return (confirmations_required)
end

@view
func is_confirmed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt, owner : felt) -> (res : felt):
    let (res) = _is_confirmed.read(tx_index=tx_index, owner=owner)
    return (res)
end

@view
func is_executed{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt) -> (res : felt):
    let (res) = _transactions.read(tx_index=tx_index, field=Transaction.executed)
    return (res)
end

func _get_transaction_calldata{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        tx_index : felt,
        calldata_index : felt,
        calldata_len : felt,
        calldata : felt*,
    ):
    if calldata_index == calldata_len:
        return ()
    end

    let (calldata_arg) = _transaction_calldata.read(tx_index=tx_index, calldata_index=calldata_index)
    assert calldata[calldata_index] = calldata_arg

    _get_transaction_calldata(
        tx_index=tx_index,
        calldata_index=calldata_index + 1,
        calldata_len=calldata_len,
        calldata=calldata,
    )
    return ()
end

@view
func get_transaction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt) -> (
        tx : Transaction,
        tx_calldata_len : felt,
        tx_calldata : felt*,
    ):
    alloc_locals

    let (to) = _transactions.read(tx_index=tx_index, field=Transaction.to)
    let (function_selector) = _transactions.read(tx_index=tx_index, field=Transaction.function_selector)
    let (calldata_len) = _transactions.read(tx_index=tx_index, field=Transaction.calldata_len)
    let (executed) = _transactions.read(tx_index=tx_index, field=Transaction.executed)
    let (num_confirmations) = _transactions.read(tx_index=tx_index, field=Transaction.num_confirmations)
    let tx = Transaction(
        to=to,
        function_selector=function_selector,
        calldata_len=calldata_len,
        executed=executed,
        num_confirmations=num_confirmations,
    )

    let (calldata) = alloc()
    if calldata_len == 0:
        return (tx=tx, tx_calldata_len=calldata_len, tx_calldata=calldata)
    end

    # Recursively get more calldata args and add them to the list
    _get_transaction_calldata(
        tx_index=tx_index,
        calldata_index=0,
        calldata_len=calldata_len,
        calldata=calldata,
    )
    return (tx=tx, tx_calldata_len=calldata_len, tx_calldata=calldata)
end

#
# Actions
#

@constructor
func constructor{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }(
        owners_len : felt,
        owners : felt*,
        confirmations_required : felt,
    ):
    with_attr error_message("invalid number of required confirmations"):
        assert_le(confirmations_required, owners_len)
    end

    _owners_len.write(value=owners_len)
    _set_owners(owners_index=0, owners_len=owners_len, owners=owners)
    _confirmations_required.write(value=confirmations_required)
    return ()
end

@external
func submit_transaction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(
        to : felt,
        function_selector : felt,
        calldata_len : felt,
        calldata : felt*,
    ):
    alloc_locals
    require_owner()

    let (tx_index) = _next_tx_index.read()

    # Store the tx descriptor
    _transactions.write(tx_index=tx_index, field=Transaction.to, value=to)
    _transactions.write(tx_index=tx_index, field=Transaction.function_selector, value=function_selector)
    _transactions.write(tx_index=tx_index, field=Transaction.calldata_len, value=calldata_len)
    # transactions[tx_index].executed = FALSE
    # transactions[tx_index].num_confirmations = 0

    # Recursively store the tx calldata
    _set_transaction_calldata(
        tx_index=tx_index,
        calldata_index=0,
        calldata_len=calldata_len,
        calldata=calldata,
    )

    # Emit event & update tx count
    let (caller) = get_caller_address()
    SubmitTransaction.emit(owner=caller, tx_index=tx_index, to=to)
    _next_tx_index.write(value=tx_index + 1)
    return ()
end

@external
func confirm_transaction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    require_owner()
    require_tx_exists(tx_index=tx_index)
    require_not_executed(tx_index=tx_index)
    require_not_confirmed(tx_index=tx_index)

    let (num_confirmations) = _transactions.read(
        tx_index=tx_index, field=Transaction.num_confirmations
    )
    _transactions.write(
        tx_index=tx_index,
        field=Transaction.num_confirmations,
        value=num_confirmations + 1,
    )
    let (caller) = get_caller_address()
    _is_confirmed.write(tx_index=tx_index, owner=caller, value=TRUE)

    ConfirmTransaction.emit(owner=caller, tx_index=tx_index)
    return ()
end

@external
func revoke_confirmation{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt):
    require_owner()
    require_tx_exists(tx_index=tx_index)
    require_not_executed(tx_index=tx_index)
    require_confirmed(tx_index=tx_index)

    let (num_confirmations) = _transactions.read(
        tx_index=tx_index, field=Transaction.num_confirmations
    )
    _transactions.write(
        tx_index=tx_index,
        field=Transaction.num_confirmations,
        value=num_confirmations - 1,
    )
    let (caller) = get_caller_address()
    _is_confirmed.write(tx_index=tx_index, owner=caller, value=FALSE)

    RevokeConfirmation.emit(owner=caller, tx_index=tx_index)
    return ()
end

@external
func execute_transaction{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(tx_index : felt) -> (
        response_len: felt,
        response: felt*,
    ):
    require_owner()
    require_tx_exists(tx_index=tx_index)
    require_not_executed(tx_index=tx_index)

    let (tx, tx_calldata_len, tx_calldata) = get_transaction(tx_index=tx_index)

    # Require minimum configured confirmations
    let (required_confirmations) = _confirmations_required.read()
    with_attr error_message("need more confirmations"):
        assert_le(required_confirmations, tx.num_confirmations)
    end

    # Mark as executed
    _transactions.write(
        tx_index=tx_index,
        field=Transaction.executed,
        value=TRUE,
    )
    let (caller) = get_caller_address()
    ExecuteTransaction.emit(owner=caller, tx_index=tx_index)

    # Actually execute it
    let response = call_contract(
        contract_address=tx.to,
        function_selector=tx.function_selector,
        calldata_size=tx_calldata_len,
        calldata=tx_calldata,
    )
    return (response_len=response.retdata_size, response=response.retdata)
end

#
# Storage Helpers
#

func _set_owners{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }(
        owners_index : felt,
        owners_len : felt,
        owners : felt*,
    ):
    if owners_index == owners_len:
        return ()
    end

     # Write the current iteration to storage
    _owners.write(index=owners_index, value=[owners])
    _is_owner.write(address=[owners], value=TRUE)

    # Recursively write the rest
    _set_owners(owners_index=owners_index + 1, owners_len=owners_len, owners=owners + 1)
    return ()
end

func _set_transaction_calldata{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
    }(
        tx_index : felt,
        calldata_index : felt,
        calldata_len : felt,
        calldata : felt*,
    ):
    if calldata_index == calldata_len:
        return ()
    end

     # Write the current iteration to storage
    _transaction_calldata.write(
        tx_index=tx_index,
        calldata_index=calldata_index,
        value=[calldata],
    )

    # Recursively write the rest
    _set_transaction_calldata(
        tx_index=tx_index,
        calldata_index=calldata_index + 1,
        calldata_len=calldata_len,
        calldata=calldata + 1,
    )
    return ()
end
