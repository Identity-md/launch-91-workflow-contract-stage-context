// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {Wager} from "../src/Wager.sol";
import {HandshakeBet} from "../src/HandshakeBet.sol";

contract LocalFactory {
    function deploy() external returns (Wager token, HandshakeBet bet) {
        token = new Wager();
        bet = new HandshakeBet(address(token));
    }
}

contract DeploymentTest is Test {
    function testFactoryDeploymentAndRuntimePolicy() public {
        LocalFactory factory = new LocalFactory();
        (Wager token, HandshakeBet bet) = factory.deploy();
        assertEq(token.balanceOf(address(factory)), 1e27);
        assertEq(address(bet.token()), address(token));
        assertEq(token.balanceOf(address(bet)), 0);
        checkRuntime(address(token).code);
        checkRuntime(address(bet).code);
    }

    function checkRuntime(bytes memory code) internal pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24576);
        for (uint256 i; i < code.length; i++) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }
}
