 # pragma version ~=0.4.0
"""
@title `prediction-v1` binary prediction market 
@custom:contract-name prediction-v1
@license GNU Affero General Public License v3.0 only
@author rabuawad
"""


# @dev We import the `IERC20` interface,
# which is a built-in interface of the Vyper compiler.
from ethereum.ercs import IERC20


# @dev We import the `IERC20Detailed` interface,
# which is a built-in interface of the Vyper compiler.
from ethereum.ercs import IERC20Detailed


# @dev We import the `AggregatorV3` interface.
from .interfaces import IAggregatorV3


# @dev We import and initialise the `ownable` module.
from snekmate.auth import ownable as ow
initializes: ow


# @dev We export all `external` functions
# from the `ownable` module.
exports: ow.__interface__


# @dev Enum representing the position of a bet,
# either BULL (Up) or BEAR (Down)
flag Position:
    BULL
    BEAR


# @dev Stores the Round data used for tracking
# each prediction round in the protocol
struct Round:
    epoch: uint256
    start_timestamp: uint256
    lock_timestamp: uint256
    close_timestamp: uint256
    lock_price: int256
    close_price: int256
    lock_oracle_round_id: uint256
    close_oracle_round_id: uint256
    total_amount: uint256
    bull_amount: uint256
    bear_amount: uint256
    reward_base_cal_amount: uint256
    reward_amount: uint256
    oracle_called: bool



# @dev Stores information about each bet,
# including position, amount and claimed status
struct BetInfo:
    position: Position
    amount: uint256
    claimed: bool


# @dev Tracks whether the genesis lock round has been triggered. This ensures
# that the price lock for the first round (genesis) is only done once.
genesis_lock_once: public(bool)


# @dev Tracks whether the gesis start round has been triggered. This ensures
# that the first round (genesis) starts only once and avoids multiple initializations.
genesis_start_once: public(bool)


# @dev Stores the address of the underlying toke (asset)
# used for by the protocol.
asset: public(immutable(address))


# @dev Stores the ERC-20 interface of the underlaying token (asset)
# used by the protocol.
_ASSET: immutable(IERC20)


# @dev Stores the address of the Chainlink Data Feed
# used by the protocol.
oracle: public(immutable(address))


# @dev Stores the Aggregator V3 object for the Data Feed
# used by the protocol.
_ORACLE: immutable(IAggregatorV3)


# @dev Returns the numbers of seconds for a valid
# execution of a prediction round.
buffer_seconds: public(uint256)


# @dev Returns the number of interval seconds between
# two prediction rounds.
interval_seconds: public(uint256)


# @dev Returns the minimum betting amount, denominated
# in wei.
min_bet_amount: public(uint256)


# @dev Returns the fee taken by the protocol on
# each prediction round.
treasury_fee: public(uint256)


# @dev Returns the amount stored in the protocol
# that has not been claimed yet.
treasury_amount: public(uint256)


# @dev Returns the current epoch for the ongoing
# prediction round.
current_epoch: public(uint256)


# @dev Returns the latests Round ID from
# the Chainlink Data Feed (converted from uint80)
oracle_latest_round_id: public(uint256)


# @dev Returns the interval of seconds
# between each oracle allowance
oracle_update_allowance: public(uint256)


# @dev Returns the maximum fee that can be
# set by the protocol's owner. Here is set
# to 10%.
MAX_TREASURY_FEE: public(constant(uint256)) = 1000


# @dev Retujrns maximum minimun bet amount that
# can be set in the protocol. Here is set to
# 0.1 of the chain's native currency or 0.1 * 10^18
MAX_MINIMUM_BET_AMOUNT: public(constant(uint256)) = 100000000000000000


# @dev Maps each epoch ID to a mapping of
# user addresses to their Bet information (BetInfo).
ledger: public(HashMap[uint256, HashMap[address, BetInfo]])


# @dev Maps each epoch ID too the corresponing
# Round data.
rounds: public(HashMap[uint256, Round])


# @dev Maps each user's address to a unique ID used
# to keep track of the user rounds.
_user_rounds: HashMap[address, uint256]


# @dev Maps each user's address to an array of epochs
# in which they have participated. We use nexted HashMaps
# to work around the limitations of dynamic arrays in Vyper.
#
# Structure:
# Address => Index => Round ID 
user_rounds: public(HashMap[address, HashMap[uint256, uint256]])


# @dev Returns the limit of ujser rounds that can be queried.
USER_ROUNDS_BOUND: constant(uint256) = max_value(uint256)


# @dev Log when a user places a Bear bet.
event BetBear:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a user places a Bull bet.
event BetBull:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a user claims their winnings.
event Claim:
    sender: indexed(address)
    epoch: indexed(uint256)
    amount: uint256


# @dev Log when a round ends.
event EndRound:
    epoch: indexed(uint256)
    round_id: indexed(uint256)
    price: int256


# @dev Log when a round is locked.
event LockRound:
    epoch: indexed(uint256)
    round_id: indexed(uint256)
    price: int256


# @dev Log when the buffer and interval
# in seconds are updated.
event NewBufferAndIntervalInSeconds:
    buffer_seconds: uint256
    interval_seconds: uint256


# @dev Log when a new minimum bet amount is set
# for the protocol.
event NewMinBetAmount:
    epoch: indexed(uint256)
    min_bet_amount: uint256


# @dev Log when a new treasury fee is set
# for the protocol.
event Newtreasury_fee:
    epoch: indexed(uint256)
    treasury_fee: uint256


# @dev Log when a new Chainlink Data Feed update
# allowance is set.
event Neworacle_update_allowance:
    oracle_update_allowance: uint256


# @dev Log when rewards are calculated for a specific
# epoch.
event RewardsCalculated:
    epoch: indexed(uint256)
    reward_base_cal_amount: uint256
    reward_amount: uint256
    treasury_amount: uint256


# @dev Log when round starts.
event StartRound:
    epoch: indexed(uint256)


# @dev Log when tokens are recovered from the contract.
event TokenRecovery:
    token: indexed(address)
    amount: uint256


# @dev Log when the treasury claims its funds.
event TreasuryClaim:
    amount: uint256


@deploy
@payable
def __init__(
    _asset: IERC20,
    _oracle: IAggregatorV3,
    _interval_seconds: uint256,
    _buffer_seconds: uint256,
    _min_bet_amount: uint256,
    _oracle_update_allowance: uint256,
    _treasury_fee: uint256
):
    """
    @dev To omit the opcodes for checking the `msg.value`
         in the creation-time EVM bytecode, the constructor
         is declared as `payable`.
    @param _asset The ERC-20 compatible (i.e. ERC-777 is also vaiable)
           underlying asset contract.
    @param _oracle The address of the Chainlink Data Feed oracle conotract
           used to provide price feed data for the protocol.
    @param _interval_seconds The interval (in seconds) at which the price
           updates occur,determinig how often the contract fetched new
           price information from the oracle.
    @param _buffer_seconds The buffer time (in seconds) that must elapse
           before a new position round can start, ensuring smooth transtions
           between rounds.
    @param _min_bet_amount The minimum amount of currency that users can wager
           when placing a bet, designed to ensure that bets are of a meaninful
           size.
    @param _oracle_update_allowance The allowance period (in seconds) within the
           oracle is expected to update the price feed data, helping to maintain
           timely information.
    @param _treasury_fee The fee collected for the treasury, which can be
           used for various operational costs or for funding other aspects
           of the protocol.
    @notice The `owner` role will be assigned to
            the `msg.sender`.
    """
    assert _treasury_fee <= MAX_TREASURY_FEE, "prediction: treasury fee to high"

    _ASSET = _asset
    asset = _ASSET.address

    _ORACLE = _oracle
    oracle = _ORACLE.address

    self.interval_seconds = _interval_seconds
    self.buffer_seconds = _buffer_seconds
    self.min_bet_amount = _min_bet_amount
    self.oracle_update_allowance = _oracle_update_allowance
    self.treasury_fee = _treasury_fee

    # The following line assigns the `owner`
    # to the `msg.sender`.
    ow.__init__()


@internal
@view
def _not_proxy_contract():
    """
    @dev Internal function to ensure that the caller
         is not a proxy contract.
    """
    assert msg.sender == tx.origin, "predictions: proxy contract is not allowed"


@view
@internal
def _bettable(epoch: uint256) -> bool:
    """
    @notice Determines whether a given round (epoch)
            is in a bettable state.
    @param epoch The epoch (round) to check.
    @return bool True if the round is bettable, False otherwise.
    @notice A round is considered bettable if:
        - It has a valid start timestamp (non-zero).
        - It has a valid lock timestamp (non-zero).
        - The current block timestamp is between the start and lock timestamps.
    """
    r: Round = self.rounds[epoch]
    return (
        r.start_timestamp != 0
        and r.lock_timestamp != 0
        and block.timestamp > r.start_timestamp
        and block.timestamp < r.lock_timestamp
    )


@view
@internal
def _claimable(epoch: uint256, user: address) -> bool:
    """
    @notice Checks if the user can claim rewards for specific epoch.
    @param epoch The round (epoch) to check.
    @param user The user's address.
    @return bool True if the user is eligible to claim, False otherwise.
    @notice The claimable status is determined by:
        - The oracle has provided final data (Round.oracle_called is set to True).
        - The user has place a bet (amount is non-zero).
        - The user has not already claimed the wards.
        - The result of the round (whether the user's position won or lost)
    """
    bet_info: BetInfo = self.ledger[epoch][user]
    r: Round = self.rounds[epoch]

    return (
        r.oracle_called
        and bet_info.amount > 0
        and not bet_info.claimed
        and (
            (r.close_price > r.lock_price and bet_info.position == Position.BULL)
            or (r.close_price < r.lock_price and bet_info.position == Position.BEAR)
        )
    )


@view
@internal
def _refundable(epoch: uint256, user: address) -> bool:
    """
    @notice Determines whether the user is eligible for a refund in a specific round (epoch).
    @param epoch The round (epoch) to check.
    @param user The user's address.
    @return bool True if the user is eligible for a refund, False otherwise.
    @notice Refundable status is determined by:
        - The oracle has not provided a final price data (Round.oracle_called is False).
        - The user has placed a bet but not yet claimed the reward.
        - The current block timestamp is greater than the round's close timestamp plus a buffer.
        - The user has plapced a bet (amount is non-zero).
    """
    bet_info: BetInfo = self.ledger[epoch][user]
    r: Round = self.rounds[epoch]

    return (
        not r.oracle_called and
        not bet_info.claimed and
        bet_info.amount != 0 and
        block.timestamp < r.close_timestamp + self.buffer_seconds
    )


@view
@internal
def _get_price_from_oracle() -> (uint80, int256):
    """
    @notice Get the latest recorded price from the oracle.
    @dev Ensures the oracle has updated within the allowed time buffer and
         checks the oracle's round ID is valid (greater that the latest stored
         round ID).
    @return round_id The round ID from the oracle.
    @return price The latests price from the oracle.
    """
    least_allowed_timestamp: uint256 = block.timestamp + self.oracle_update_allowance

    round_id: uint80 = 0
    answer: int256 = 0
    started_at: uint256 = 0
    updated_at: uint256 = 0
    answered_in_round: uint80 = 0
    (round_id, answer, started_at, updated_at, answered_in_round) = staticcall _ORACLE.latestRoundData()

    assert block.timestamp <= least_allowed_timestamp, "prediction: oracle update exceeded max timestamp allowance"
    assert convert(round_id, uint256) > self.oracle_latest_round_id, "prediction: oracle update round_id must be larger than oracleLatestround_id"

    return round_id, answer


@internal
def _safe_end_round(epoch: uint256, round_id: uint256, price: int256):
    """
    @notice End a specific round by locking in the closing price and oracle round ID.
    @dev This function ensures the round is locked and can only be ended after the close_timestamp,
         but within the buffer_seconds.
    @param epoch The round (epoch) to be ended
    @param round_id the oracle's round ID for this round. Chainlink Data Feeds return a round 
           ID that needs to be stored in the Round struct.
    @param price The closing price for this round.
    """
    r: Round = self.rounds[epoch]

    assert r.lock_timestamp != 0, "prediction: can only end round after round has locked"
    assert block.timestamp >= r.close_timestamp, "prediction: can only end round after close_timestamp"
    assert block.timestamp <= r.close_timestamp + self.buffer_seconds, "prediction: can only end round within buffer_seconds"

    self.rounds[epoch].close_price = price
    self.rounds[epoch].close_oracle_round_id = round_id
    self.rounds[epoch].oracle_called = True
    log EndRound(epoch, round_id, price)


@internal
def _safe_lock_round(epoch: uint256, round_id: uint256, price: int256):
    """
    @notice Lock a specific round by setting the lock price and oracle round ID.
    @dev This function ensures that the round has started and can only be locked after
         the lock_timestamp, but within buffer_seconds.
    @param epoch The round (epoch) to be locked.
    @param round_id the oracle's round ID for this round. Chainlink Data Feeds return a round 
           ID that needs to be stored in the Round struct.
    @param price The locking price for this round.
    """
    r: Round = self.rounds[epoch]

    assert r.start_timestamp != 0, "prediction: can only lock round after round has started"
    assert block.timestamp >= r.lock_timestamp, "prediction: can only lock round after lock_timestamp"
    assert block.timestamp <= r.lock_timestamp + self.buffer_seconds, "prediction: can only round within bufferSeonds"

    self.rounds[epoch].close_timestamp = block.timestamp + self.interval_seconds
    self.rounds[epoch].lock_price = price
    self.rounds[epoch].lock_oracle_round_id = round_id
    log LockRound(epoch, round_id, price)


@internal
def _start_round(epoch: uint256):
    """
    @notice Start a specific round by initializing the round's timestamps and settings the epoch.
    @dev This function sets the start, lock, and close timestamps for the round and resets the total amount.
    @param epoch The round (epoch) to be started.
    """
    interval_seconds: uint256 = self.interval_seconds

    self.rounds[epoch].start_timestamp = block.timestamp
    self.rounds[epoch].lock_timestamp = block.timestamp + interval_seconds
    self.rounds[epoch].close_timestamp = block.timestamp + (2 * interval_seconds)
    self.rounds[epoch].epoch = epoch
    self.rounds[epoch].total_amount = 0
    log StartRound(epoch)


@internal
def _safe_start_round(epoch: uint256):
    """
    @notice Start a new round by validating the status of the previous round.
    @dev this function ensures that the genesis round has started and the n-2 round has ended before
         starting a new round.
    @param epoch The round (epoch) to e started.
    """
    r: Round = self.rounds[epoch - 2]

    assert self.genesis_start_once, "prediction: can only run after genesisStartRound is triggered"
    assert r.close_timestamp != 0, "prediction: can only start a new round after the round n-2 has ended"
    assert block.timestamp >= r.close_timestamp, "prediction: can only start a new round after round n-2 close_timestamp"

    self._start_round(epoch)


@internal
def _calculate_rewards(epoch: uint256):
    """
    @notice Calculate the rewards for a specific round based on the closing and locking prices.
    @dev Rewards are calculated based on the comparasion of the closing price with the locking price.
         The function handles three scenarios: bull winds, bear wins, and house wins.
    @param The round (epoch) for which rewards are being calculated.
    """
    r: Round = self.rounds[epoch]
    assert r.reward_base_cal_amount == 0 and r.reward_amount == 0, "prediction: rewards already calculated"

    reward_base_cal_amount: uint256 = 0
    treasury_amount: uint256 = 0
    reward_amount: uint256 = 0

    # Bull wins (close price is greater than the lock price)
    if r.close_price > r.lock_price:
        reward_base_cal_amount = r.bull_amount
        treasury_amount = (r.total_amount * self.treasury_fee) // 10000
        reward_amount = r.total_amount - treasury_amount
    
    # Bear wins (close price is less than the lock price)
    elif r.close_price < r.lock_price:
        reward_base_cal_amount = r.bear_amount
        treasury_amount = (r.total_amount * self.treasury_fee) // 10000
        reward_amount = r.total_amount - treasury_amount
    
    # House wins (close price equals the lock price)
    else:
        reward_base_cal_amount = 0
        treasury_amount = r.total_amount
        reward_amount = 0
    
    self.rounds[epoch].reward_base_cal_amount = reward_base_cal_amount
    self.rounds[epoch].reward_amount = reward_amount
    
    self.treasury_amount += treasury_amount
    log RewardsCalculated(epoch, reward_base_cal_amount, reward_amount, treasury_amount)


@external
@view
def claimable(epoch: uint256, user: address) -> bool:
    """
    @notice Checks if the user can claim rewards for specific epoch.
    @param epoch The round (epoch) to check.
    @param user The user's address.
    @return bool True if the user is eligible to claim, False otherwise.
    """
    return self._claimable(epoch, user)


@view
@external
def refundable(epoch: uint256, user: address) -> bool:
    """
    @notice Determines whether the user is eligible for a refund in a specific round (epoch).
    @param epoch The round (epoch) to check.
    @param user The user's address.
    @return bool True if the user is eligible for a refund, False otherwise.
    """
    return self._refundable(epoch, user)
