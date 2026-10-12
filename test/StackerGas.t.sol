// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseTest} from "./Base.t.sol";
import {Stacker} from "../src/Stacker.sol";

/// @dev Test-only integration of the README's gas guard, bounded call and plain-IMD fallback.
contract GasBudgetProject {
    Stacker internal immutable stacker;
    IERC20 internal immutable imd;

    constructor(Stacker stacker_, IERC20 imd_) {
        stacker = stacker_;
        imd = imd_;
        imd_.approve(address(stacker_), type(uint256).max);
    }

    function pay(address trader, uint256 cashback) external returns (uint256 shares) {
        require(gasleft() >= 410_000, "imd/acc: insufficient gas");
        try stacker.credit{gas: 350_000}(trader, cashback) returns (uint256 minted) {
            return minted;
        } catch {
            require(imd.transfer(trader, cashback), "IMD transfer failed");
            return 0;
        }
    }
}

contract StackerGasTest is BaseTest {
    GasBudgetProject internal hook;
    address internal project = makeAddr("gas project");
    address internal trader = makeAddr("gas trader");

    function setUp() public override {
        super.setUp();
        hook = new GasBudgetProject(stacker, IERC20(address(imd)));
        deal(address(imd), address(hook), 10e18);
        fund(project, 10e18, type(uint256).max);
    }

    function test_oldGasCapFailsRepeatedlyAndDoesNotPrimeVault() public {
        for (uint256 i; i < 2; ++i) {
            vm.prank(project);
            (bool ok, bytes memory data) =
                address(stacker).call{gas: 177_000}(abi.encodeCall(Stacker.credit, (trader, 1e18)));
            assertFalse(ok, "136k x 1.3 cannot fund first-use setup");
            assertEq(data.length, 0, "out of gas, not a token/vault error");
            assertEq(imd.allowance(address(stacker), address(sImd)), 0);
            assertEq(imd.balanceOf(project), 10e18);
            assertEq(imd.balanceOf(address(stacker)), 0);
            assertEq(sImd.totalSupply(), 0);
            assertEq(stacker.projectStacked(project), 0);
            assertEq(stacker.projectShares(project), 0);
            assertEq(stacker.totalStacked(), 0);
        }

        vm.prank(project);
        stacker.credit(trader, 1e18);
        address secondTrader = makeAddr("second gas trader");
        vm.prank(project);
        (bool later,) = address(stacker).call{gas: 177_000}(
            abi.encodeCall(Stacker.credit, (secondTrader, 1e18))
        );
        assertTrue(later, "the same cap works after first-use setup");
        assertEq(stacker.totalStacked(), 2e18);
    }

    function test_readmeBudgetFundsColdFirstCredit() public {
        // Only 1k above the documented check, to cover entry/ABI decoding before gasleft().
        uint256 shares = hook.pay{gas: 411_000}(trader, 1e18);
        assertGt(shares, 0, "cashback did not silently take the fallback");
        assertEq(sImd.balanceOf(trader), shares);
        assertEq(imd.balanceOf(trader), 0);
        assertEq(imd.balanceOf(address(hook)), 9e18);
        assertEq(stacker.projectStacked(address(hook)), 1e18);
        assertEq(imd.allowance(address(stacker), address(sImd)), type(uint256).max);
        assertEq(imd.balanceOf(address(stacker)), 0);
        assertEq(sImd.balanceOf(address(stacker)), 0);
    }

    function test_readmeGasGuardRejectsLowEstimateBeforeFallback() public {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "imd/acc: insufficient gas"));
        hook.pay{gas: 400_000}(trader, 1e18);
        assertEq(imd.balanceOf(address(hook)), 10e18);
        assertEq(imd.balanceOf(trader), 0);
        assertEq(sImd.balanceOf(trader), 0);
        assertEq(stacker.totalStacked(), 0);
        assertEq(imd.allowance(address(stacker), address(sImd)), 0);
    }

    function test_readmeFallbackPaysPlainImdWhenVaultFails() public {
        vm.prank(OWNER);
        sImd.setPaused(true);
        assertEq(hook.pay{gas: 411_000}(trader, 1e18), 0);
        assertEq(imd.balanceOf(trader), 1e18);
        assertEq(imd.balanceOf(address(hook)), 9e18);
        assertEq(sImd.balanceOf(trader), 0);
        assertEq(stacker.totalStacked(), 0);
        assertEq(imd.allowance(address(stacker), address(sImd)), 0);
    }

    function test_readmeFallbackHasGasEvenWhenCreditExhaustsItsBudget() public {
        // Simulate an external vault consuming all the forwarded gas during first-use validation.
        // INVALID exceptionally halts its call and burns that call's remaining gas.
        vm.etch(address(sImd), hex"fe");
        assertEq(hook.pay{gas: 411_000}(trader, 1e18), 0);
        assertEq(imd.balanceOf(trader), 1e18);
        assertEq(imd.balanceOf(address(hook)), 9e18);
        assertEq(imd.balanceOf(address(stacker)), 0);
        assertEq(stacker.totalStacked(), 0);
        assertEq(imd.allowance(address(stacker), address(sImd)), 0);
    }
}
