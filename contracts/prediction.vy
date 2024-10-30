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


# @dev Returns the address of the operator.
operator: public(address)


# @dev Returns if the contract is paused, or not.
paused: public(bool)


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
event NewTreasuryFee:
    epoch: indexed(uint256)
    treasury_fee: uint256


# @dev Log when a new Chainlink Data Feed update
# allowance is set.
event NewOracleUpdateAllowance:
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


# @dev Log when the contract is paused for a specific epoch
event Pause:
    epoch: indexed(uint256)


# @dev Log when the contract is unpaused for a specific epoch
event Unpause:
    epoch: indexed(uint256)


# @dev Log when a new operator address is set
event NewOperatorAddress:
    operator: address


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


@internal
@view
def _only_operator():
    """
    @dev Internal function to ensure the method is called only by the operator.
    """
    assert msg.sender == self.operator, "prediction: caller is not operator"


@internal
@view
def _when_not_paused():
    """
    @dev Internal function to ensure the protocol is not paused.
    """
    assert not self.paused, "prediction: protocol is paused"


@internal
@view
def _when_paused():
    """
    @dev Internal function to ensure the protocol is paused.
    """
    assert self.paused, "prediction: protocol is not paused"
 

@view
@internal
def _bettable(epoch: uint256) -> bool:
    """
    @notice Determines whether a given round (epoch)
            is in a bettable state.
    @param epoch The epoch (round) to check.
    @return bool True if the round is bettable, False otherwise.
    @dev A round is considered bettable if:
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
    @dev The claimable status is determined by:
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
    @dev Refundable status is determined by:
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
    assert block.timestamp <= r.lock_timestamp + self.buffer_seconds, "prediction: can only lock round within bufferSeonds"

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


@nonreentrant
@external
def pause():
    """
    @notice Pauses the protocol, triggering a stop state.
    @dev Callable by owner only. Once paused the contracts enters a stopped state
         and cannot be interacted with for certain functions until unpaused.
    """
    ow._check_owner()
    assert not self.paused, "prediction: contract is already paused"

    self.paused = True
    log Pause(self.current_epoch)


@nonreentrant
@external
def unpause():
    """
    @notice Unpauses the contract and returns to normal operation.
    @dev Callable by owner only. This function resets the genesis state, and once unpaused,
         the rounds need to be restarted by triggering the genesis start.
    """
    ow._check_owner()
    assert self.paused, "prediction: contract is not paused"

    self.genesis_start_once = False
    self.genesis_lock_once = False
    self.paused = False
    log Unpause(self.current_epoch)
    

@nonreentrant
@external
def bet_bear(epoch: uint256, amount: uint256):
    """
    @notice Allows a user to place a bet on the bear position for a specific round.
    @param epoch The round (epoch) in which the bet is placed.
    @param amount The amount beign wagered.
    @dev
        - The epoch must match the current epoch.
        - The round must be bettable.
        - The bet amount must be greater than the minimum bet amount.
        - The user can only bet once per round.
    """
    self._not_proxy_contract()
    self._when_not_paused()

    assert epoch == self.current_epoch, "prediction: bet is too early/late"
    assert self._bettable(epoch), "prediction: round is not bettable"
    assert amount >= self.min_bet_amount, "prediction: bet amount must be greater than min_bet_amount"
    assert self.ledger[epoch][msg.sender].amount == 0, "prediction: can only bet once per round"

    extcall _ASSET.transferFrom(msg.sender, self, amount)

    self.rounds[epoch].total_amount += amount
    self.rounds[epoch].bear_amount += amount

    self.ledger[epoch][msg.sender].position = Position.BEAR
    self.ledger[epoch][msg.sender].amount = amount

    # Get the Round ID for that corresponding user
    i: uint256 = self._user_rounds[msg.sender]
    self._user_rounds[msg.sender] += 1
    self.user_rounds[msg.sender][i] = epoch

    log BetBear(msg.sender, epoch, amount)


@nonreentrant
@external
def bet_bull(epoch: uint256, amount: uint256):
    """
    @dev Allows a user to place a bet on the bear position for a specific epoch.
    @param epoch The round (epoch) in which the bet is placed.
    @param amount The amount beign wagered.
    @dev
        - The epoch must match the current epoch.
        - The round must be bettable.
        - The bet amount must be greater than the minimum bet amount.
        - The user can only bet once per round.
    """
    self._not_proxy_contract()
    self._when_not_paused()

    assert epoch == self.current_epoch, "prediction: bet is too early/late"
    assert self._bettable(epoch), "prediction: round not bettable"
    assert amount >= self.min_bet_amount, "prediction: bet amount must be greater than min_bet_amount"
    assert self.ledger[epoch][msg.sender].amount == 0, "prediction: can only bet once per round"

    extcall _ASSET.transferFrom(msg.sender, self, amount)

    self.rounds[epoch].total_amount += amount
    self.rounds[epoch].bear_amount += amount

    self.ledger[epoch][msg.sender].position = Position.BULL
    self.ledger[epoch][msg.sender].amount = amount

    # Get the Round ID for that corresponding user
    i: uint256 = self._user_rounds[msg.sender]
    self._user_rounds[msg.sender] += 1
    self.user_rounds[msg.sender][i] = epoch

    log BetBull(msg.sender, epoch, amount)


@nonreentrant
@external
def claim(epochs: DynArray[uint256, 128]):
    """
    @notice Claims rewards for an array of epochs (rounds).
    @param epochs And array of epochs (round ids).
    """
    self._not_proxy_contract()
    self._when_not_paused()
    
    reward: uint256 = 0
    for epoch: uint256 in epochs:
        r: Round = self.rounds[epoch]

        assert r.start_timestamp != 0, "prediction: round has not started"
        assert r.close_timestamp < block.timestamp, "prediction: round has not ended"

        added_rewards: uint256 = 0
        if r.oracle_called:
            assert self._claimable(epoch, msg.sender), "prediction: not eligible for claim"
            added_rewards = (self.ledger[epoch][msg.sender].amount * r.reward_amount) // r.reward_base_cal_amount
        else:
            assert self._refundable(epoch, msg.sender), "prediction: not eligible for refund"
            added_rewards = (self.ledger[epoch][msg.sender].amount * r.reward_amount) // r.reward_base_cal_amount
        
        self.ledger[epoch][msg.sender].claimed = True
        reward += added_rewards

        log Claim(msg.sender, epoch, added_rewards)
    
    if reward > 0:
        extcall _ASSET.transfer(msg.sender, reward)


@nonreentrant
@external
def genesis_start_round():
    """
    @notice Start the genesis round.
    @dev Callable only by the operator. It can only be run once to initialize
         the first round of the protocol.
    """
    self._only_operator()
    self._when_not_paused()

    assert not self.genesis_start_once, "prediction: can only run genesis_start_round once"

    self.current_epoch += 1
    self._start_round(self.current_epoch)
    self.genesis_start_once = True


@nonreentrant
@external
def genesis_lock_round():
    """
    @notice Lock the gensis round.
    @dev Callable only by the operator. Requires that the genesis start round has been
         triggered and that the genesis lock round has not been executed yet. After locking, it
         starts the next round and updates the state.
    """
    self._only_operator()
    self._when_not_paused()

    assert self.genesis_start_once, "prediction: can only run after genesis_start_round is triggered"
    assert not self.genesis_lock_once, "prediction: can only run genesis_lock_round once"

    current_round_id: uint80 = 0
    current_price: int256 = 0
    current_round_id, current_price = self._get_price_from_oracle()

    oracle_latest_round_id: uint256 = convert(current_round_id, uint256)
    self.oracle_latest_round_id = oracle_latest_round_id

    current_epoch: uint256 = self.current_epoch
    self._safe_lock_round(current_epoch, oracle_latest_round_id, current_price)
    self.current_epoch += 1

    self._start_round(current_epoch+1)
    self.genesis_lock_once = True
    

@nonreentrant
@external
def execute_round():
    """
    @notice Start the next round (n), lock the price for round (n-1), and end round (n-2).
    @dev Callable only by the operator. Requires that genesis_start_once and
         genesis_lock_once have been triggered before this can be executed.
    """
    self._only_operator()
    self._not_proxy_contract()
    self._when_not_paused()

    assert self.genesis_start_once and self.genesis_lock_once, "prediction: can only run after genesis_start_round and genesis_lock_round are triggered"

    current_round_id: uint80 = 0
    current_price: int256 = 0
    current_round_id, current_price = self._get_price_from_oracle()

    oracle_latest_round_id: uint256 = convert(current_round_id, uint256)
    self.oracle_latest_round_id = oracle_latest_round_id

    current_epoch: uint256 = self.current_epoch
    self._safe_lock_round(current_epoch, oracle_latest_round_id, current_price)
    self._safe_end_round(current_epoch-1, oracle_latest_round_id, current_price)

    self._calculate_rewards(current_epoch-1)

    self.current_epoch += 1
    self._safe_start_round(current_epoch+1)
    

@nonreentrant
@external
def claim_treasury():
    """
    @notice Claim all rewards stored in the treasury.
    @dev Callable by owner only. This function transfer all the treasury funds to the admin
         address and resets the treasury amount to zero.
    """
    ow._check_owner()

    current_treasury_amount: uint256 = self.treasury_amount
    self.treasury_amount = 0

    extcall _ASSET.transfer(ow.owner, current_treasury_amount)
    log TreasuryClaim(current_treasury_amount)


@external
def set_buffer_and_interval_seconds(buffer_seconds: uint256, interval_seconds: uint256):
    """
    @notice Set buffer and interval (in seconds)
    @param buffer_seconds The buffer duration in seconds
    @param interval_seconds The interval duration in seconds
    @dev Callable by owner when paused
    """
    ow._check_owner()
    self._when_paused()
    assert buffer_seconds < interval_seconds, "prediction: buffer_seconds must be less than interval_seconds"

    self.buffer_seconds = buffer_seconds
    self.interval_seconds = interval_seconds
    log NewBufferAndIntervalInSeconds(buffer_seconds, interval_seconds)
    

@external
def set_min_bet_amount(min_bet_amount: uint256):
    """
    @notice Set the minimum bet amount
    @param min_bet_amount The minimum amount that can be bet
    @dev Callable by owner when the contract is paused
    """
    ow._check_owner()
    self._when_paused()
    assert min_bet_amount != 0, "prediction: min_bet_amount must be greater than 0"
    assert min_bet_amount >= MAX_MINIMUM_BET_AMOUNT, "prediction: minimum bet amount is too low"
    
    self.min_bet_amount = min_bet_amount
    log NewMinBetAmount(self.current_epoch, min_bet_amount)


@external
def set_operator(operator: address):
    """
    @notice Set the operator address
    @param operator The address of the new operator
    @dev Callable by onwer
    """
    ow._check_owner()
    assert operator != empty(address), "prediction: operator cannot be zero address"
    self.operator = operator
    log NewOperatorAddress(operator)


@external
def set_oracle_update_allowance(oracle_update_allowance: uint256):
    """
    @notice Set the oracle update allowance in seconds
    @param oracle_update_allowance New allowance value for oracle updates
    @dev Callable by owner when paused
    """
    ow._check_owner()

    self.oracle_update_allowance = oracle_update_allowance
    log NewOracleUpdateAllowance(oracle_update_allowance)


@external
def set_treasury_fee(treasury_fee: uint256):
    """
    @notice Set the treasury fee percentage
    @param treasury_fee New treasury fee, must not exceed the max allowed
    @dev Callable by owner when paused
    """
    ow._check_owner()
    assert treasury_fee <= MAX_TREASURY_FEE, "prediction: Treasury fee too high"
    
    self.treasury_fee = treasury_fee
    log NewTreasuryFee(self.current_epoch, treasury_fee)


@nonreentrant
@external
def recover_token(token: address, amount: uint256):
    """
    @notice Allows the owner to recover tokens mistakenly sent to the contract
    @param token The token address
    @param amount The amount of tokens to recover
    @dev Callable by owner
    """
    ow._check_owner()
    assert token != _ASSET.address, "prediction: cannot be prediction token address"

    extcall IERC20(token).transfer(msg.sender, amount)
    log TokenRecovery(token, amount)


@view
@external
def get_user_rounds(user: address, cursor: uint256, size: uint256) -> (DynArray[uint256, 1024], DynArray[BetInfo, 1024], uint256):
    """
    @notice Returns round epochs and bet information for a user that has participated
    @param user The address of the user
    @param cursor The cursor (starting point in the userRounds array)
    @param size The number of rounds to retrieve
    @return A tuple containing:
        - A list of round epochs the user has participated in
        - A list of bet information associated with the rounds
        - The updated cursor after retrieving the requested rounds
    """
    length: uint256 = size

    if length > self._user_rounds[user] - cursor:
        length = self._user_rounds[user] - cursor

    values: DynArray[uint256, 1024] = []
    bet_info: DynArray[BetInfo, 1024] = []

    for i: uint256 in range(length, bound=USER_ROUNDS_BOUND):
        round_epoch: uint256 = self.user_rounds[user][cursor+i]
        values.append(round_epoch)
        bet_info.append(self.ledger[round_epoch][user])

    return values, bet_info, (cursor+length)


@view
@external
def get_user_rounds_length(user: address) -> uint256:
    """
    @notice Returns the number of rounds a user has participated in
    @param user The address of the user
    @return The length of the userRounds list for the user
    """
    return self._user_rounds[user]