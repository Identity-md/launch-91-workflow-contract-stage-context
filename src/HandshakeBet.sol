// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IWager {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Bilateral statement wagers settled by agreement, with permissionless timeout refunds.
contract HandshakeBet {
    enum State {
        Missing,
        Proposed,
        Accepted,
        Resolved
    }
    enum Outcome {
        Unset,
        ProposerWins,
        CounterpartyWins
    }

    struct Bet {
        address proposer;
        address counterparty;
        uint256 stake;
        uint256 deadline;
        bytes32 statement;
        State state;
        Outcome proposerOutcome;
        Outcome counterpartyOutcome;
    }

    IWager public immutable token;
    uint256 public constant GRACE_PERIOD = 7 days;
    uint256 public nextBetId;
    mapping(uint256 => Bet) public bets;
    mapping(address => uint256) public claimable;
    bool private entered;

    error InvalidBet();
    error InvalidTerms();
    error Unauthorized();
    error WrongState();
    error WrongTime();
    error InvalidOutcome();
    error AlreadySubmitted();
    error NothingToClaim();
    error TokenTransferFailed();
    error Reentrancy();

    event Proposed(
        uint256 indexed id,
        address indexed proposer,
        address indexed counterparty,
        uint256 stake,
        uint256 deadline,
        bytes32 statement
    );
    event Accepted(uint256 indexed id);
    event OutcomeSubmitted(uint256 indexed id, address indexed party, Outcome outcome);
    /// @dev Unset means refund; amounts are credits, withdrawn with claim().
    event Resolved(uint256 indexed id, Outcome outcome, uint256 proposerCredit, uint256 counterpartyCredit);
    event Claimed(address indexed party, uint256 amount);

    constructor(address tokenAddress) {
        if (tokenAddress.code.length == 0) revert InvalidTerms();
        token = IWager(tokenAddress);
    }

    modifier nonReentrant() {
        if (entered) revert Reentrancy();
        entered = true;
        _;
        entered = false;
    }

    function propose(address counterparty, uint256 stake, uint256 deadline, bytes32 statement)
        external
        nonReentrant
        returns (uint256 id)
    {
        if (
            counterparty == address(0) || counterparty == msg.sender || counterparty == address(this) || stake == 0
                || stake > type(uint256).max / 2 || deadline <= block.timestamp
                || deadline > type(uint256).max - GRACE_PERIOD || statement == bytes32(0)
        ) revert InvalidTerms();
        id = nextBetId++;
        bets[id] =
            Bet(msg.sender, counterparty, stake, deadline, statement, State.Proposed, Outcome.Unset, Outcome.Unset);
        emit Proposed(id, msg.sender, counterparty, stake, deadline, statement);
        _deposit(msg.sender, stake);
    }

    function accept(uint256 id) external nonReentrant {
        Bet storage bet = _bet(id);
        if (bet.state != State.Proposed) revert WrongState();
        if (msg.sender != bet.counterparty) revert Unauthorized();
        if (block.timestamp >= bet.deadline) revert WrongTime();
        bet.state = State.Accepted;
        emit Accepted(id);
        _deposit(msg.sender, bet.stake);
    }

    /// @notice Proposer may cancel only an unmatched proposal.
    function cancel(uint256 id) external nonReentrant {
        Bet storage bet = _bet(id);
        if (msg.sender != bet.proposer) revert Unauthorized();
        if (bet.state != State.Proposed) revert WrongState();
        _resolve(id, bet, Outcome.Unset, bet.stake, 0);
    }

    /// @notice Claims are final. ProposerWins means the statement is true, CounterpartyWins false.
    function submitOutcome(uint256 id, Outcome outcome) external nonReentrant {
        Bet storage bet = _bet(id);
        if (bet.state != State.Accepted) revert WrongState();
        if (block.timestamp < bet.deadline || block.timestamp >= bet.deadline + GRACE_PERIOD) revert WrongTime();
        if (outcome == Outcome.Unset) revert InvalidOutcome();
        if (msg.sender == bet.proposer) {
            if (bet.proposerOutcome != Outcome.Unset) revert AlreadySubmitted();
            bet.proposerOutcome = outcome;
        } else if (msg.sender == bet.counterparty) {
            if (bet.counterpartyOutcome != Outcome.Unset) revert AlreadySubmitted();
            bet.counterpartyOutcome = outcome;
        } else {
            revert Unauthorized();
        }
        emit OutcomeSubmitted(id, msg.sender, outcome);
        if (bet.proposerOutcome != Outcome.Unset && bet.counterpartyOutcome != Outcome.Unset) {
            if (bet.proposerOutcome != bet.counterpartyOutcome) _resolve(id, bet, Outcome.Unset, bet.stake, bet.stake);
            else if (outcome == Outcome.ProposerWins) _resolve(id, bet, outcome, bet.stake * 2, 0);
            else _resolve(id, bet, outcome, 0, bet.stake * 2);
        }
    }

    /// @notice Anyone can expire an unmatched proposal or a timed-out accepted bet.
    function expire(uint256 id) external nonReentrant {
        Bet storage bet = _bet(id);
        if (bet.state == State.Proposed) {
            if (block.timestamp < bet.deadline) revert WrongTime();
            _resolve(id, bet, Outcome.Unset, bet.stake, 0);
        } else if (bet.state == State.Accepted) {
            if (block.timestamp < bet.deadline + GRACE_PERIOD) revert WrongTime();
            _resolve(id, bet, Outcome.Unset, bet.stake, bet.stake);
        } else {
            revert WrongState();
        }
    }

    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingToClaim();
        claimable[msg.sender] = 0;
        emit Claimed(msg.sender, amount);
        uint256 beforeBalance = token.balanceOf(address(this));
        uint256 beforeRecipient = token.balanceOf(msg.sender);
        if (!token.transfer(msg.sender, amount)) revert TokenTransferFailed();
        if (
            token.balanceOf(address(this)) != beforeBalance - amount
                || token.balanceOf(msg.sender) != beforeRecipient + amount
        ) revert TokenTransferFailed();
    }

    function _deposit(address from, uint256 amount) private {
        uint256 beforeBalance = token.balanceOf(address(this));
        if (!token.transferFrom(from, address(this), amount)) revert TokenTransferFailed();
        if (token.balanceOf(address(this)) != beforeBalance + amount) revert TokenTransferFailed();
    }

    function _bet(uint256 id) private view returns (Bet storage bet) {
        bet = bets[id];
        if (bet.state == State.Missing) revert InvalidBet();
    }

    function _resolve(uint256 id, Bet storage bet, Outcome outcome, uint256 proposerCredit, uint256 counterpartyCredit)
        private
    {
        bet.state = State.Resolved;
        claimable[bet.proposer] += proposerCredit;
        claimable[bet.counterparty] += counterpartyCredit;
        emit Resolved(id, outcome, proposerCredit, counterpartyCredit);
    }
}
