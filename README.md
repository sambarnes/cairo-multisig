# 👥 cairo-multisig

A multisig contract written in Cairo, following [a reference implementation](https://solidity-by-example.org/app/multi-sig-wallet/) from solidity-by-example.

> ⚠️ WARNING: This is not intended for production use. The code has barely been tested, let alone audited.

It is built under the assumption that all owners will have their own [OpenZeppelin Account](https://github.com/OpenZeppelin/cairo-contracts/blob/main/docs/Account.md) or similar.

Available actions:
* `submit_transaction` -- submit a new transaction for approval
* `confirm_transaction` -- confirm/approve a transaction for one owner
* `revoke_confirmation` -- undo a previous approval for one owner
* `execute_transaction` -- execute the submitted transaction once minimum confirmations reached

## Development

```
python3.7 -m venv venv
source venv/bin/activate
python -m pip install cairo-nile
nile install
```

Needs way more tests, but super basic coverage can be run using the following:

```
(venv) ~/dev/eth/starknet/cairo-multisig$ make test
pytest tests/
================================= test session starts =================================
platform darwin -- Python 3.9.8, pytest-7.0.1, pluggy-1.0.0
rootdir: /Users/sam/dev/eth/starknet/cairo-multisig
plugins: web3-5.28.0, typeguard-2.13.3, asyncio-0.18.1
asyncio: mode=legacy
collected 4 items

tests/test_contract.py ....                                                     [100%]

=========================== 4 passed, 3 warnings in 56.27s ============================
```

## Potential next steps

* More tests
* Allow for transferring partial/full ownership
