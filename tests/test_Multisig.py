import asyncio

import pytest
from starkware.starknet.public.abi import get_selector_from_name
from starkware.starknet.testing.starknet import Starknet
from starkware.starkware_utils.error_handling import StarkException

from utils import Signer


signer0 = Signer(123456789987654321)
signer1 = Signer(987654321123456789)

TRUE, FALSE = 1, 0


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def multisig_factory():
    starknet = await Starknet.empty()
    owner0 = await starknet.deploy(
        "contracts/Account.cairo",
        constructor_calldata=[signer0.public_key],
    )
    owner1 = await starknet.deploy(
        "contracts/Account.cairo",
        constructor_calldata=[signer1.public_key],
    )

    confirmations_required = 1
    multisig = await starknet.deploy(
        "contracts/Multisig.cairo",
        constructor_calldata=[
            2,
            owner0.contract_address,
            owner1.contract_address,
            confirmations_required,
        ],
    )

    initializable = await starknet.deploy(
        "contracts/Initializable.cairo",
        constructor_calldata=[],
    )
    return starknet, multisig, owner0, owner1, initializable


@pytest.mark.asyncio
async def test_constructor(multisig_factory):
    _, multisig, owner0, owner1, _ = multisig_factory

    expected_len = 2
    observed = await multisig.get_owners_len().call()
    assert observed.result.owners_len == expected_len

    observed = await multisig.get_owners().call()
    assert len(observed.result.owners) == expected_len
    assert observed.result.owners[0] == owner0.contract_address
    assert observed.result.owners[1] == owner1.contract_address

    expected_confirmations_required = 1
    observed = await multisig.get_confirmations_required().call()
    assert observed.result.confirmations_required == expected_confirmations_required


@pytest.mark.asyncio
async def test_submit_transaction(multisig_factory):
    _, multisig, owner0, _, initializable = multisig_factory

    observed = await multisig.get_transactions_len().call()
    assert observed.result.res == 0
    observed = await initializable.initialized().call()
    assert observed.result.res == FALSE, "Example contract started in incorrect state"

    # Submit the first transaction
    tx_index = 0
    to = initializable.contract_address
    function_selector = get_selector_from_name("initialize")
    calldata_len = 1
    calldata = 0
    await signer0.send_transaction(
        account=owner0,
        to=multisig.contract_address,
        selector_name="submit_transaction",
        calldata=[to, function_selector, calldata_len, calldata]
    )

    # Check it was accepted & starts as unconfirmed
    observed = await multisig.get_transactions_len().call()
    assert observed.result.res == 1
    observed = await multisig.is_confirmed(tx_index=tx_index, owner=owner0.contract_address).call()
    assert observed.result.res == FALSE


@pytest.mark.asyncio
async def test_execute_unconfirmed_transaction(multisig_factory):
    _, multisig, owner0, _, initializable = multisig_factory

    # Execute it without confirming
    tx_index = 0
    with pytest.raises(StarkException):
        await signer0.send_transaction(
            account=owner0,
            to=multisig.contract_address,
            selector_name="execute_transaction",
            calldata=[tx_index]
        )
    # Check our initial state still holds
    observed = await multisig.is_executed(tx_index=tx_index).call()
    assert observed.result.res == FALSE
    observed = await initializable.initialized().call()
    assert observed.result.res == FALSE


@pytest.mark.asyncio
async def test_execute_confirmed_transaction(multisig_factory):
    _, multisig, owner0, _, initializable = multisig_factory

    # Confirm it for the owner
    tx_index = 0
    await signer0.send_transaction(
        account=owner0,
        to=multisig.contract_address,
        selector_name="confirm_transaction",
        calldata=[tx_index]
    )
    observed = await multisig.is_confirmed(tx_index=tx_index, owner=owner0.contract_address).call()
    assert observed.result.res == TRUE

    # Execute it
    await signer0.send_transaction(
        account=owner0,
        to=multisig.contract_address,
        selector_name="execute_transaction",
        calldata=[tx_index]
    )
    observed = await multisig.is_executed(tx_index=tx_index).call()
    assert observed.result.res == TRUE
    observed = await initializable.initialized().call()
    assert observed.result.res == TRUE
