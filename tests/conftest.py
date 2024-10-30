import pytest
import boa


@pytest.fixture(scope="module")
def accounts():
    initial_balance = int(10e18)
    accounts = [boa.env.generate_address() for _ in range(10)]
    for account in accounts:
        boa.env.set_balance(account, initial_balance)
    return accounts


@pytest.fixture(scope="module")
def owner():
    initial_balance = int(10e18)
    owner = boa.env.generate_address()
    boa.env.set_balance(owner, initial_balance)
    return owner
