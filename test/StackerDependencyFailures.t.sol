// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseTest} from "./Base.t.sol";
import {TestIMD} from "./mocks/TestIMD.sol";
import {TestSIMD} from "./mocks/TestSIMD.sol";
import {Stacker, IStakedIMD} from "src/Stacker.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Fault injection at Stacker's calls, after the normal token effects. These modes are not
/// claims about live IMD: they test whether a dependency failure can leave partial cashback.
contract FailureResponseIMD is TestIMD {
    address public stacker;
    uint8 public approvalFailure;
    uint8 public pullFailure;

    error TokenRejected();

    function configure(address target, uint8 approveMode, uint8 pullMode) external {
        stacker = target;
        approvalFailure = approveMode;
        pullFailure = pullMode;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        super.approve(spender, amount);
        return _response(msg.sender == stacker ? approvalFailure : 0);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        return _response(msg.sender == stacker ? pullFailure : 0);
    }

    function _response(uint8 mode) internal pure returns (bool) {
        if (mode == 1) return false;
        if (mode == 2) revert TokenRejected();
        if (mode == 3) {
            // A complete word, but not a valid ABI true value.
            assembly ("memory-safe") {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return true;
    }
}

/// @dev Mint and transfer for real, then truncate the ABI response. Decoding failure must unwind
/// the mint, the receiver's hold, both transfers, the finite allowance and first-use setup.
contract TruncatedResponseSIMD is TestSIMD {
    uint256 public returnLength = 32;

    constructor(address asset_, address owner_) TestSIMD(asset_, owner_) {}

    function setReturnLength(uint256 length) external {
        returnLength = length;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        shares = super.deposit(assets, receiver);
        uint256 length = returnLength;
        assembly ("memory-safe") {
            mstore(0, shares)
            return(0, length)
        }
    }
}

/// forge-config: default.fuzz.runs = 1000
contract StackerDependencyFailuresTest is BaseTest {
    FailureResponseIMD internal token;
    TruncatedResponseSIMD internal vault;
    address internal project = makeAddr("dependency failure project");
    address internal trader = makeAddr("dependency failure trader");

    function setUp() public override {
        super.setUp();
        token = new FailureResponseIMD();
        vault = new TruncatedResponseSIMD(address(token), OWNER);
        imd = token;
        sImd = vault;
        stacker = new Stacker(IERC20(address(token)), IStakedIMD(address(vault)));
        token.configure(address(stacker), 0, 0);
        fund(project, 100_000e18, 100_000e18);
    }

    function test_falseApprovalRollsBackAndNextCreditRevalidates() public {
        _tokenFailure(1, true, false, 1e18);
    }

    function test_revertingApprovalRollsBackAndNextCreditRevalidates() public {
        _tokenFailure(2, true, false, 1e18);
    }

    function test_invalidBooleanApprovalRollsBack() public {
        _tokenFailure(3, true, false, 1e18);
    }

    function test_falsePullAfterMovingOneWeiRollsBackFirstApproval() public {
        _tokenFailure(1, false, false, 1);
    }

    function test_revertingPullBubblesErrorAfterAnEarlierCredit() public {
        _tokenFailure(2, false, true, 1e18);
    }

    function test_invalidBooleanPullRollsBack() public {
        _tokenFailure(3, false, false, 1e18);
    }

    function testFuzz_tokenFailureIsAtomic(uint8 mode, uint96 amount, bool initialized) public {
        _tokenFailure(uint8(bound(mode, 1, 3)), false, initialized, bound(amount, 1, 50_000e18));
    }

    function _tokenFailure(uint8 mode, bool approval, bool initialized, uint256 amount) internal {
        if (initialized) _credit(10e18);
        bytes32 before_ = _state();
        token.configure(address(stacker), approval ? mode : 0, approval ? 0 : mode);
        bytes memory expected = mode == 2
            ? abi.encodeWithSelector(FailureResponseIMD.TokenRejected.selector)
            : abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token));
        _reject(amount, expected);
        assertEq(_state(), before_, "dependency error left partial state");
        token.configure(address(stacker), 0, 0);
        _recover(initialized, amount);
    }

    function test_missingDepositReturnRollsBackActualMint() public {
        _truncatedDeposit(0, false, 1);
    }

    function test_oneByteShortDepositReturnRollsBackActualMintAndHold() public {
        _truncatedDeposit(31, true, 1e18);
    }

    function testFuzz_shortDepositReturnIsAtomic(uint8 length, bool initialized, uint96 amount)
        public
    {
        _truncatedDeposit(bound(length, 0, 31), initialized, bound(amount, 1, 50_000e18));
    }

    function _truncatedDeposit(uint256 length, bool initialized, uint256 amount) internal {
        if (initialized) _credit(10e18);
        vm.roll(block.number + 1); // a failed deposit must not renew an existing hold
        bytes32 before_ = _state();
        vault.setReturnLength(length);
        _reject(amount, bytes("")); // Solidity's ABI decoder rejects a short uint256 response
        assertEq(_state(), before_, "ABI decoding failure must roll back the entire credit");
        vault.setReturnLength(32);
        _recover(initialized, amount);
    }

    function testFuzz_shortAssetReturnFailsBeforeAnyApproval(uint8 length) public {
        bytes32 before_ = _state();
        vm.mockCall(
            address(vault), abi.encodeCall(IStakedIMD.asset, ()), new bytes(bound(length, 0, 31))
        );
        _reject(1e18, bytes(""));
        assertEq(_state(), before_);
        vm.clearMockedCalls();
        _recover(false, 1e18);
    }

    function test_dirtyAssetAddressIsRejectedBeforeAnyApproval() public {
        bytes32 before_ = _state();
        uint256 dirtyAddress = uint256(uint160(address(token))) | (uint256(1) << 160);
        vm.mockCall(address(vault), abi.encodeCall(IStakedIMD.asset, ()), abi.encode(dirtyAddress));
        _reject(1e18, bytes(""));
        assertEq(_state(), before_);
        vm.clearMockedCalls();
        _recover(false, 1e18);
    }

    function test_assetRevertDataBubblesAndDoesNotPrimeApproval() public {
        bytes memory reason = abi.encodeWithSignature("Unavailable(uint256)", 1294);
        bytes32 before_ = _state();
        vm.mockCallRevert(address(vault), abi.encodeCall(IStakedIMD.asset, ()), reason);
        _reject(1e18, reason);
        assertEq(_state(), before_);
        vm.clearMockedCalls();
        _recover(false, 1e18);
    }

    function _reject(uint256 amount, bytes memory expected) internal {
        vm.prank(project);
        (bool ok, bytes memory reason) =
            address(stacker).call(abi.encodeCall(Stacker.credit, (trader, amount)));
        assertFalse(ok, "a failed dependency must not count as cashback");
        assertEq(reason, expected, "unexpected failure reason");
    }

    function _recover(bool initialized, uint256 amount) internal {
        if (!initialized) {
            // Observe the private readiness flag through behavior, without depending on layout.
            vm.mockCall(address(vault), abi.encodeCall(IStakedIMD.asset, ()), abi.encode(project));
            _reject(
                amount,
                abi.encodeWithSelector(Stacker.AssetMismatch.selector, project, address(token))
            );
            assertEq(imd.allowance(address(stacker), address(vault)), 0);
            vm.clearMockedCalls();
        }
        uint256 totalBefore = stacker.totalStacked();
        uint256 sharesBefore = vault.balanceOf(trader);
        uint256 shares = _credit(amount);
        assertGt(shares, 0, "failure did not poison reentrancy guard or initialization");
        assertEq(vault.balanceOf(trader), sharesBefore + shares);
        assertEq(stacker.totalStacked(), totalBefore + amount);
        assertEq(imd.balanceOf(address(stacker)), 0);
        assertEq(vault.balanceOf(address(stacker)), 0);
    }

    function _credit(uint256 amount) internal returns (uint256 shares) {
        vm.prank(project);
        shares = stacker.credit(trader, amount);
    }

    function _state() internal view returns (bytes32) {
        bytes32 tokenState = keccak256(
            abi.encode(
                imd.balanceOf(project),
                imd.balanceOf(address(stacker)),
                imd.balanceOf(address(vault)),
                imd.allowance(project, address(stacker)),
                imd.allowance(address(stacker), address(vault))
            )
        );
        return keccak256(
            abi.encode(
                tokenState,
                vault.balanceOf(trader),
                vault.totalSupply(),
                vault.lastDepositBlock(trader),
                stacker.projectStacked(project),
                stacker.projectShares(project),
                stacker.totalStacked()
            )
        );
    }
}
