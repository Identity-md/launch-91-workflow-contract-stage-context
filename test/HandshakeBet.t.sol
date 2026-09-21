// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {Wager} from "../src/Wager.sol";
import {HandshakeBet, IWager} from "../src/HandshakeBet.sol";

contract HandshakeBetTest is Test {
    Wager token;
    HandshakeBet bet;
    address alice = address(1);
    address bob = address(2);
    address outsider = address(3);
    uint256 constant STAKE = 10 ether;
    uint256 constant DEADLINE = 1000;
    bytes32 constant STATEMENT = keccak256("The statement is true");

    function setUp() public {
        vm.warp(100);
        token = new Wager();
        bet = new HandshakeBet(address(token));
        token.transfer(alice, 100 ether);
        token.transfer(bob, 100 ether);
        vm.prank(alice);
        token.approve(address(bet), type(uint256).max);
        vm.prank(bob);
        token.approve(address(bet), type(uint256).max);
    }

    function propose() internal returns (uint256 id) {
        vm.prank(alice);
        id = bet.propose(bob, STAKE, DEADLINE, STATEMENT);
    }

    function accept() internal returns (uint256 id) {
        id = propose();
        vm.prank(bob);
        bet.accept(id);
    }

    function testFuzzAgreement(bool proposerWins, bool reverseOrder) public {
        uint256 id = accept();
        vm.warp(DEADLINE);
        HandshakeBet.Outcome outcome =
            proposerWins ? HandshakeBet.Outcome.ProposerWins : HandshakeBet.Outcome.CounterpartyWins;
        vm.prank(reverseOrder ? bob : alice);
        bet.submitOutcome(id, outcome);
        assertEq(bet.claimable(alice) + bet.claimable(bob), 0);
        vm.prank(reverseOrder ? alice : bob);
        bet.submitOutcome(id, outcome);
        address winner = proposerWins ? alice : bob;
        assertEq(bet.claimable(winner), 2 * STAKE);
        vm.prank(winner);
        bet.claim();
        assertEq(token.balanceOf(winner), 110 ether);
        assertEq(token.balanceOf(address(bet)), 0);
        vm.expectRevert(HandshakeBet.NothingToClaim.selector);
        vm.prank(winner);
        bet.claim();
        vm.expectRevert(HandshakeBet.WrongState.selector);
        bet.expire(id);
    }

    function testDisagreementRefundsImmediately() public {
        uint256 id = accept();
        vm.warp(DEADLINE);
        vm.prank(alice);
        bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        vm.prank(bob);
        bet.submitOutcome(id, HandshakeBet.Outcome.CounterpartyWins);
        assertEq(bet.claimable(alice), STAKE);
        assertEq(bet.claimable(bob), STAKE);
        vm.prank(alice);
        bet.claim();
        vm.prank(bob);
        bet.claim();
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.balanceOf(address(bet)), 0);
    }

    function testFuzzSilenceRefunds(uint8 submitted) public {
        submitted = uint8(bound(submitted, 0, 2));
        uint256 id = accept();
        vm.warp(DEADLINE);
        if (submitted > 0) {
            vm.prank(submitted == 1 ? alice : bob);
            bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        }
        vm.warp(DEADLINE + 7 days - 1);
        vm.expectRevert(HandshakeBet.WrongTime.selector);
        bet.expire(id);
        vm.warp(DEADLINE + 7 days);
        vm.expectRevert(HandshakeBet.WrongTime.selector);
        vm.prank(bob);
        bet.submitOutcome(id, HandshakeBet.Outcome.CounterpartyWins);
        vm.prank(outsider);
        bet.expire(id);
        assertEq(bet.claimable(alice), STAKE);
        assertEq(bet.claimable(bob), STAKE);
    }

    function testUnmatchedCancellationAndExpiry() public {
        uint256 id = propose();
        vm.expectRevert(HandshakeBet.Unauthorized.selector);
        vm.prank(bob);
        bet.cancel(id);
        vm.expectRevert(HandshakeBet.WrongTime.selector);
        bet.expire(id);
        vm.prank(alice);
        bet.cancel(id);
        vm.expectRevert(HandshakeBet.WrongState.selector);
        vm.prank(bob);
        bet.accept(id);
        id = propose();
        vm.warp(DEADLINE);
        vm.expectRevert(HandshakeBet.WrongTime.selector);
        vm.prank(bob);
        bet.accept(id);
        bet.expire(id);
        assertEq(bet.claimable(alice), 2 * STAKE);
        vm.prank(alice);
        bet.claim();
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function testAuthorizationDuplicatesAndBoundaries() public {
        uint256 id = propose();
        vm.expectRevert(HandshakeBet.Unauthorized.selector);
        vm.prank(outsider);
        bet.accept(id);
        vm.warp(DEADLINE - 1);
        vm.prank(bob);
        bet.accept(id);
        vm.expectRevert(HandshakeBet.WrongState.selector);
        vm.prank(bob);
        bet.accept(id);
        vm.expectRevert(HandshakeBet.WrongState.selector);
        vm.prank(alice);
        bet.cancel(id);
        vm.expectRevert(HandshakeBet.WrongTime.selector);
        vm.prank(alice);
        bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        vm.warp(DEADLINE);
        vm.expectRevert(HandshakeBet.Unauthorized.selector);
        vm.prank(outsider);
        bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        vm.expectRevert(HandshakeBet.InvalidOutcome.selector);
        vm.prank(alice);
        bet.submitOutcome(id, HandshakeBet.Outcome.Unset);
        vm.prank(alice);
        bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        vm.expectRevert(HandshakeBet.AlreadySubmitted.selector);
        vm.prank(alice);
        bet.submitOutcome(id, HandshakeBet.Outcome.CounterpartyWins);
        vm.warp(DEADLINE + 7 days - 1);
        vm.prank(bob);
        bet.submitOutcome(id, HandshakeBet.Outcome.ProposerWins);
        assertEq(bet.claimable(alice), 2 * STAKE);
    }

    function testInvalidTermsAndMissingIds() public {
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        new HandshakeBet(address(0));
        address[3] memory invalid = [address(0), alice, address(bet)];
        for (uint256 i; i < invalid.length; i++) {
            vm.expectRevert(HandshakeBet.InvalidTerms.selector);
            vm.prank(alice);
            bet.propose(invalid[i], STAKE, DEADLINE, STATEMENT);
        }
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        bet.propose(bob, 0, DEADLINE, STATEMENT);
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        bet.propose(bob, type(uint256).max, DEADLINE, STATEMENT);
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        bet.propose(bob, STAKE, 100, STATEMENT);
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        bet.propose(bob, STAKE, type(uint256).max, STATEMENT);
        vm.expectRevert(HandshakeBet.InvalidTerms.selector);
        bet.propose(bob, STAKE, DEADLINE, bytes32(0));
        vm.expectRevert(HandshakeBet.InvalidBet.selector);
        bet.accept(99);
        vm.expectRevert(HandshakeBet.InvalidBet.selector);
        bet.cancel(99);
        vm.expectRevert(HandshakeBet.InvalidBet.selector);
        bet.expire(99);
        vm.expectRevert(HandshakeBet.InvalidBet.selector);
        bet.submitOutcome(99, HandshakeBet.Outcome.ProposerWins);
    }

    function testInsufficientApprovalAndBalanceRollback() public {
        vm.prank(alice);
        token.approve(address(bet), STAKE - 1);
        vm.expectRevert(Wager.InsufficientAllowance.selector);
        propose();
        assertEq(bet.nextBetId(), 0);
        vm.prank(alice);
        token.approve(address(bet), STAKE);
        uint256 id = propose();
        vm.prank(bob);
        token.transfer(outsider, 100 ether);
        vm.expectRevert(Wager.InsufficientBalance.selector);
        vm.prank(bob);
        bet.accept(id);
        (,,,,, HandshakeBet.State state,,) = bet.bets(id);
        assertEq(uint256(state), uint256(HandshakeBet.State.Proposed));
        assertEq(token.balanceOf(address(bet)), STAKE);
    }

    function testFuzzConservationAcrossBets(uint96 rawStake) public {
        uint256 amount = bound(uint256(rawStake), 1, 40 ether);
        vm.prank(alice);
        uint256 first = bet.propose(bob, amount, DEADLINE, STATEMENT);
        vm.prank(bob);
        bet.accept(first);
        vm.prank(bob);
        uint256 second = bet.propose(alice, amount, DEADLINE, STATEMENT);
        vm.prank(alice);
        bet.accept(second);
        vm.warp(DEADLINE);
        vm.prank(alice);
        bet.submitOutcome(first, HandshakeBet.Outcome.ProposerWins);
        vm.prank(bob);
        bet.submitOutcome(first, HandshakeBet.Outcome.ProposerWins);
        vm.warp(DEADLINE + 7 days);
        bet.expire(second);
        assertEq(bet.claimable(alice) + bet.claimable(bob), token.balanceOf(address(bet)));
        vm.prank(alice);
        bet.claim();
        vm.prank(bob);
        bet.claim();
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), 200 ether);
        assertEq(token.balanceOf(address(bet)), 0);
    }
}

/// @dev Deliberately adversarial token for transfer failure, short transfer and callback tests.
contract HostileToken is IWager {
    mapping(address => uint256) public balanceOf;
    bool public fail;
    bool public shortTransfer;
    address public target;
    bytes public callback;
    bool public attempted;
    bool public reentrySucceeded;
    bytes4 public reentryError;

    function mint(address who, uint256 amount) external {
        balanceOf[who] += amount;
    }

    function configure(bool failure, bool shortAmount, address receiver, bytes calldata data) external {
        fail = failure;
        shortTransfer = shortAmount;
        target = receiver;
        callback = data;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return move(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return move(from, to, amount);
    }

    function move(address from, address to, uint256 amount) internal returns (bool) {
        if (fail) return false;
        if (target != address(0)) {
            attempted = true;
            (bool success, bytes memory result) = target.call(callback);
            reentrySucceeded = success;
            if (result.length >= 4) reentryError = bytes4(result);
        }
        balanceOf[from] -= amount;
        balanceOf[to] += shortTransfer ? amount - 1 : amount;
        return true;
    }
}

contract AdversarialTokenTest is Test {
    HostileToken token;
    HandshakeBet bet;

    function setUp() public {
        vm.warp(100);
        token = new HostileToken();
        bet = new HandshakeBet(address(token));
        token.mint(address(this), 100);
        token.mint(address(2), 100);
    }

    function propose() internal returns (uint256) {
        return bet.propose(address(2), 10, 1000, bytes32(uint256(1)));
    }

    function testFalseAndShortDepositsRollback() public {
        for (uint256 i; i < 2; i++) {
            token.configure(i == 0, i == 1, address(0), "");
            vm.expectRevert(HandshakeBet.TokenTransferFailed.selector);
            propose();
            assertEq(bet.nextBetId(), 0);
            assertEq(token.balanceOf(address(bet)), 0);
        }
    }

    function testAcceptTokenFailureRemainsUnmatched() public {
        uint256 id = propose();
        for (uint256 i; i < 2; i++) {
            token.configure(i == 0, i == 1, address(0), "");
            vm.expectRevert(HandshakeBet.TokenTransferFailed.selector);
            vm.prank(address(2));
            bet.accept(id);
            (,,,,, HandshakeBet.State state,,) = bet.bets(id);
            assertEq(uint256(state), uint256(HandshakeBet.State.Proposed));
            assertEq(token.balanceOf(address(bet)), 10);
        }
        token.configure(false, false, address(0), "");
        vm.prank(address(2));
        bet.accept(id);
        assertEq(token.balanceOf(address(bet)), 20);
    }

    function testEveryMutatingEntryPointRejectsCallback() public {
        bytes[] memory calls = new bytes[](6);
        calls[0] = abi.encodeCall(bet.propose, (address(2), 1, 1000, bytes32(uint256(1))));
        calls[1] = abi.encodeCall(bet.accept, (0));
        calls[2] = abi.encodeCall(bet.cancel, (0));
        calls[3] = abi.encodeCall(bet.submitOutcome, (0, HandshakeBet.Outcome.ProposerWins));
        calls[4] = abi.encodeCall(bet.expire, (0));
        calls[5] = abi.encodeCall(bet.claim, ());
        for (uint256 i; i < calls.length; i++) {
            token.configure(false, false, address(bet), calls[i]);
            propose();
            assertTrue(token.attempted());
            assertFalse(token.reentrySucceeded());
            assertEq(token.reentryError(), HandshakeBet.Reentrancy.selector);
        }
        assertEq(bet.nextBetId(), 6);
        assertEq(token.balanceOf(address(bet)), 60);
    }

    function testClaimFailurePreservesCreditAndCanRetry() public {
        uint256 id = propose();
        bet.cancel(id);
        for (uint256 i; i < 2; i++) {
            token.configure(i == 0, i == 1, address(0), "");
            vm.expectRevert(HandshakeBet.TokenTransferFailed.selector);
            bet.claim();
            assertEq(bet.claimable(address(this)), 10);
            assertEq(token.balanceOf(address(bet)), 10);
        }
        token.configure(false, false, address(0), "");
        bet.claim();
        assertEq(bet.claimable(address(this)), 0);
        assertEq(token.balanceOf(address(this)), 100);
    }

    function testReentrancyOnDepositAcceptAndClaim() public {
        token.configure(
            false, false, address(bet), abi.encodeCall(bet.propose, (address(2), 1, 1000, bytes32(uint256(1))))
        );
        uint256 id = propose();
        assertTrue(token.attempted());
        assertFalse(token.reentrySucceeded());
        assertEq(token.reentryError(), HandshakeBet.Reentrancy.selector);
        assertEq(bet.nextBetId(), 1);
        token.configure(false, false, address(bet), abi.encodeCall(bet.expire, (id)));
        vm.prank(address(2));
        bet.accept(id);
        assertFalse(token.reentrySucceeded());
        assertEq(token.reentryError(), HandshakeBet.Reentrancy.selector);
        vm.warp(1000 + 7 days);
        bet.expire(id);
        token.configure(false, false, address(bet), abi.encodeCall(bet.claim, ()));
        bet.claim();
        assertFalse(token.reentrySucceeded());
        assertEq(token.reentryError(), HandshakeBet.Reentrancy.selector);
        assertEq(bet.claimable(address(this)), 0);
        assertEq(token.balanceOf(address(bet)), 10);
    }
}
