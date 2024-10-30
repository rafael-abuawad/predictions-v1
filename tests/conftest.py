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


@pytest.fixture(scope="module")
def asset(owner):
    name = "Wrapped ETH"
    symbol = "WETH"
    decimals = 18
    initial_supply = 1_000_000
    name_eip712 = "fake_weth"
    version_eip712 = "0.0.1"
    with boa.env.prank(owner):
        asset = boa.load(
            "tests/mocks/erc20_mock.vy",
            name,
            symbol,
            decimals,
            initial_supply,
            name_eip712,
            version_eip712,
        )
    return asset


@pytest.fixture(scope="module")
def oracle():
    decimals = 8
    initial_answer = int(2000e8)
    oracle = boa.load("tests/mocks/aggregator_v3_mock.vy", decimals, initial_answer)
    return oracle


@pytest.fixture(scope="module")
def prediction(owner, asset, oracle):
    interval_in_seconds = 300
    buffer_in_seconds = 15
    min_bet_amount = int(0.01e18)
    oracle_update_allowance = 300
    treasury_fee = 1000

    with boa.env.prank(owner):
        prediction = boa.load(
            "contracts/prediction.vy",
            asset.address,
            oracle.address,
            interval_in_seconds,
            buffer_in_seconds,
            min_bet_amount,
            oracle_update_allowance,
            treasury_fee,
        )
    return prediction
