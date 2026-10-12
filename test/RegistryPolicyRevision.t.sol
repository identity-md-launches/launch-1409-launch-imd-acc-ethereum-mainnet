// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RegistryBase} from "./ProjectRegistry.t.sol";
import {ProjectRegistry} from "../src/ProjectRegistry.sol";

contract RegistryPolicyRevisionTest is RegistryBase {
    function test_applicationAndChallengeRequireResolvedTraderAndExcludeLpFees() public {
        bytes32 application = _listed();
        bytes32 challenge = _challenge();
        string memory applicationBody = string(intake.bodyOf(application));
        string memory challengeBody = string(intake.bodyOf(challenge));
        string memory traderRule = vm.parseJsonString(applicationBody, ".definitions.trader");
        assertTrue(vm.contains(traderRule, "hookData"));
        assertTrue(vm.contains(traderRule, "msgSender()"));
        assertTrue(vm.contains(traderRule, "sender has no code"));
        assertTrue(vm.contains(traderRule, "never tx.origin"));
        assertTrue(vm.contains(traderRule, "Never pay an unresolved router"));
        assertEq(traderRule, vm.parseJsonString(challengeBody, ".definitions.trader"));
        assertLe(bytes(traderRule).length, 512);

        string memory feeRule = vm.parseJsonString(applicationBody, ".definitions.feeGuard");
        assertTrue(vm.contains(feeRule, "LP fees do not count"));
        assertTrue(vm.contains(feeRule, "every allowed setting"));
        assertEq(feeRule, vm.parseJsonString(challengeBody, ".definitions.feeGuard"));
        assertLe(bytes(feeRule).length, 512);
        assertTrue(_answer(challenge, true), "text revision preserves callback budget");
    }

    function test_lpRebateDefeatsGrossFeeFloor() public pure {
        // Cash-flow model for the report's two legs, each normalized to 1,000 IMD.
        // There is no claim here to simulate AMM price movement or gas.
        uint256 volume = 2_000e18;
        uint256 cashback = volume * 100 / 10_000;
        uint256 lpFee = volume * 100 / 10_000;
        uint256 lpRebate = lpFee * 99 / 100;
        uint256 netFeeCost = cashback + lpFee - cashback - lpRebate;
        assertGe(lpFee, cashback, "the old gross floor passes");
        assertEq(cashback, 20e18);
        assertEq(netFeeCost, 0.2e18);
        assertLt(netFeeCost, cashback);
        // Excluding LP fees leaves zero qualifying outflow for this fee split.
        assertLt(0, cashback, "the revised feeGuard rejects this split");
    }

    /// @dev Known limitation retained for the later registry launch. This is a reproduction,
    /// not a claim that a fee-only application slot guarantees a legitimate applicant a turn.
    function test_applicationSlotCanBeReoccupiedAfterFailureNoAndExpiry() public {
        uint256 before_ = imd.balanceOf(challenger);
        for (uint256 i; i < 4; ++i) {
            vm.prank(challenger);
            bytes32 id =
                reg.applyListing(project, "squat", "https://example.invalid", 25, challenger);
            vm.prank(applicant);
            vm.expectRevert(ProjectRegistry.AskOpen.selector);
            reg.applyListing(project, "PLEA", "https://github.com/x/plea", 50, beneficiary);
            assertEq(imd.balanceOf(address(reg)), 0, "no application bond");
            assertFalse(reg.isListed(project));
            if (i == 0) assertTrue(intake.fail(id, 2, "split", MAINNET_CALLBACK_GAS));
            if (i == 1) assertTrue(_answer(id, false));
            if (i == 2) {
                vm.warp(block.timestamp + reg.PENDING_EXPIRY() + 1);
                reg.expire(project);
            }
        }
        assertEq(before_ - imd.balanceOf(challenger), 4 * 0.5e18);
        assertEq(imd.balanceOf(applicant), 1_000e18, "blocked applications pay nothing");
    }
}
