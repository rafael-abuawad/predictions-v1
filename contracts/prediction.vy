 # pragma version ~=0.4.0
"""
@title `prediction` Prediction Market Game 
@custom:contract-name prediction
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
# either Bull (Up) or Bear (Down)
flag Position:
    Bull
    Bear


# @dev Stores the Round data used for tracking
# each prediction round in the protocol
struct Round:
    epoch: uint256
    startTimestamp: uint256
    lockTimestamp: uint256
    closeTimestamp: uint256
    lockPrice: int256
    closePrice: int256
    lockOracleId: uint256
    closeOracleId: uint256
    totalAmount: uint256
    bullAmount: uint256
    bearAmount: uint256
    rewardBaseCalAmount: uint256
    rewardAmount: uint256
    oracleCalled: bool


# @dev Stores information about each bet,
# including position, amount and claimed status
struct BetInfo:
    position: Position
    amount: uint256
    claimed: bool


# @dev Tracks whether the genesis lock round has been triggered. This ensures
# that the price lock for the first round (genesis) is only done once.
genesisLockOnce: public(bool)


# @dev Tracks whether the gesis start round has been triggered. This ensures
# that the first round (genesis) starts only once and avoids multiple initializations.
genesisStartOnce: public(bool)


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
bufferSeconds: public(uint256)


# @dev Returns the number of interval seconds between
# two prediction rounds.
intervalSeconds: public(uint256)


# @dev Returns the minimum betting amount, denominated
# in wei.
minBetAmount: public(uint256)


# @dev Returns the fee taken by the protocol on
# each prediction round.
treasuryFee: public(uint256)


# @dev Returns the amount stored in the protocol
# that has not been claimed yet.
treasuryAmount: public(uint256)


# @dev Returns the current epoch for the ongoing
# prediction round.
currentEpoch: public(uint256)


# @dev Returns the latests Round ID from
# the Chainlink Data Feed (converted from uint80)
oracleLatestsRoundId: public(uint256)


# @dev Returns the interval of seconds
# between each oracle allowance
oracleUpdateAllowance: public(uint256)


# @dev Returns the maximum fee that can be
# set by the protocol's owner. Here is set
# to 10%.
MAX_TREASURY_FEE: public(constant(uint256)) = 1000


# @dev Retujrns maximum minimun bet amount that
# can be set in the protocol. Here is set to
# 0.1 of the chain's native currency or 0.1 * 10^18
MAX_MINIMUM_BET_AMOUNT: public(constant(uint256)) = 100000000000000000


# @dev Maps each epoch ID to a mapping of
# user addresses to their BetInfo.
ledger: public(HashMap[uint256, HashMap[address, BetInfo]])


# @dev Maps each epoch ID too the corresponing
# Round data.
rounds: public(HashMap[uint256, Round])


# @dev Maps each user's address to a unique ID used
# to keep track of the user rounds.
_userRounds: HashMap[address, uint256]


# @dev Maps each user's address to an array of epochs
# in which they have participated. We use nexted HashMaps
# to work around the limitations of dynamic arrays in Vyper.
#
# Structure:
# Address => Index => Round ID 
userRounds: public(HashMap[address, HashMap[uint256, uint256]])


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
    roundId: indexed(uint256)
    price: int256


# @dev Log when a round is locked.
event LockRound:
    epoch: indexed(uint256)
    roundId: indexed(uint256)
    price: int256


# @dev Log when the buffer and interval
# in seconds are updated.
event NewBufferAndIntervalInSeconds:
    bufferSeconds: uint256
    intervalSeconds: uint256


# @dev Log when a new minimum bet amount is set
# for the protocol.
event NewMinBetAmount:
    epoch: indexed(uint256)
    minBetAmount: uint256


# @dev Log when a new treasury fee is set
# for the protocol.
event NewTreasuryFee:
    epoch: indexed(uint256)
    treasuryFee: uint256


# @dev Log when a new Chainlink Data Feed update
# allowance is set.
event NewOracleUpdateAllowance:
    oracleUpdateAllowance: uint256


# @dev Log when rewards are calculated for a specific
# epoch.
event RewardsCalculated:
    epoch: indexed(uint256)
    rewardBaseCalAmount: uint256
    rewardAmount: uint256
    treasuryAmount: uint256


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
    _intervalSeconds: uint256,
    _bufferSeconds: uint256,
    _minBetAmount: uint256,
    _oracleUpdateAllowance: uint256,
    _treasuryFee: uint256
):
    """
    @dev To omit the opcodes for checking the `msg.value`
         in the creation-time EVM bytecode, the constructor
         is declared as `payable`.
    @param _asset The ERC-20 compatible (i.e. ERC-777 is also vaiable)
           underlying asset contract.
    @param _oracle The address of the Chainlink Data Feed oracle conotract
           used to provide price feed data for the protocol.
    @param _intervalSeconds The interval (in seconds) at which the price
           updates occur,determinig how often the contract fetched new
           price information from the oracle.
    @param _bufferSeconds The buffer time (in seconds) that must elapse
           before a new position round can start, ensuring smooth transtions
           between rounds.
    @param _minBetAmount The minimum amount of currency that users can wager
           when placing a bet, designed to ensure that bets are of a meaninful
           size.
    @param _oracleUpdateAllowance The allowance period (in seconds) within the
           oracle is expected to update the price feed data, helping to maintain
           timely information.
    @param _treasuryFee The fee collected for the treasury, which can be
           used for various operational costs or for funding other aspects
           of the protocol.
    @notice The `owner` role will be assigned to
            the `msg.sender`.
    """
    assert _treasuryFee <= MAX_TREASURY_FEE, "prediction: treasury fee to high"

    _ASSET = _asset
    asset = _ASSET.address

    _ORACLE = _oracle
    oracle = _ORACLE.address

    self.intervalSeconds = _intervalSeconds
    self.bufferSeconds = _bufferSeconds
    self.minBetAmount = _minBetAmount
    self.oracleUpdateAllowance = _oracleUpdateAllowance
    self.treasuryFee = _treasuryFee

    # The following line assigns the `owner`
    # to the `msg.sender`.
    ow.__init__()
