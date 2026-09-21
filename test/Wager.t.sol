// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {Wager} from "../src/Wager.sol";

contract WagerTest is Test {
    Wager token;
    address alice = address(1);
    address bob = address(2);

    function setUp() public {
        token = new Wager();
    }

    function testSupplyAndMetadata() public view {
        assertEq(token.name(), "Wager");
        assertEq(token.symbol(), "WGR");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27);
    }

    function testFuzzTransfers(uint256 amount) public {
        amount = bound(amount, 0, 1e27);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), 1e27 - amount);
        vm.prank(alice);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), 1e27);
    }

    function testAllowances() public {
        token.approve(alice, 20);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 10);
        assertEq(token.allowance(address(this), alice), 10);
        vm.expectRevert(Wager.InsufficientAllowance.selector);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 11);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 10);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        token.approve(alice, 0);
        vm.expectRevert(Wager.InsufficientAllowance.selector);
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
    }

    function testInvalidTransfersAndNoMint() public {
        vm.expectRevert(Wager.InvalidRecipient.selector);
        token.transfer(address(0), 1);
        vm.expectRevert(Wager.InsufficientBalance.selector);
        vm.prank(alice);
        token.transfer(bob, 1);
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", alice, 1));
        assertFalse(ok);
        assertEq(token.totalSupply(), 1e27);
    }
}
