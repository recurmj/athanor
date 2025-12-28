// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "./lib/IERC20.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";
import {ECDSA} from "./lib/ECDSA.sol";
import {EIP712} from "./lib/EIP712.sol";
import {Ownable} from "./lib/Ownable.sol";
import {ReentrancyGuard} from "./lib/ReentrancyGuard.sol";
import {IAthanorStrategy} from "./IAthanorStrategy.sol";

interface IAthanorConsentRegistry {
    struct Authorization {
        address grantor;
        address tokenIn;
        uint256 maxPerInterval;
        uint256 intervalSeconds;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
        address strategy;
    }

    function revoked(address grantor, bytes32 nonce) external view returns (bool);
    function remainingBudget(Authorization calldata a) external view returns (uint256 remaining, uint256 windowStart);
    function recordPull(Authorization calldata a, uint256 amount) external;
}

/// @notice Permissioned pull executor for Athanor.
/// @dev Validates EIP-712 Authorization, enforces revocation and per-interval cap via the registry,
///      then calls strategy. Returns assets back to the grantor after execution.
contract AthanorPullExecutor is EIP712, Ownable, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    event Pulled(bytes32 indexed authHash, address indexed grantor, address indexed tokenIn, uint256 amount);
    event Returned(bytes32 indexed authHash, address indexed grantor, address indexed token, uint256 amount);
    event NoAction(bytes32 indexed authHash, string reason);

    event Rescue(address indexed token, address indexed to, uint256 amount);
    event RescueETH(address indexed to, uint256 amount);

    error BAD_SIG();
    error REVOKED();
    error NOT_YET_VALID();
    error EXPIRED();
    error BAD_AMOUNT();
    error NO_BUDGET();
    error BAD_INTERVAL();
    error STRATEGY_FAILED();
    error ETH_RETURN_FAILED();

    bytes32 public constant AUTH_TYPEHASH = keccak256(
        "Authorization(address grantor,address tokenIn,uint256 maxPerInterval,uint256 intervalSeconds,uint256 validAfter,uint256 validBefore,bytes32 nonce,address strategy)"
    );

    IAthanorConsentRegistry public immutable registry;

    constructor(address _registry) EIP712("AthanorPullExecutor", "1") Ownable(msg.sender) {
        registry = IAthanorConsentRegistry(_registry);
    }

    function authHash(Authorization calldata a) public pure returns (bytes32) {
        return keccak256(
            abi.encode(a.grantor, a.tokenIn, a.maxPerInterval, a.intervalSeconds, a.validAfter, a.validBefore, a.nonce, a.strategy)
        );
    }

    function structHash(Authorization calldata a) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AUTH_TYPEHASH,
                a.grantor,
                a.tokenIn,
                a.maxPerInterval,
                a.intervalSeconds,
                a.validAfter,
                a.validBefore,
                a.nonce,
                a.strategy
            )
        );
    }

    /// @notice Non-reverting signature check.
    function verify(Authorization calldata a, bytes calldata sig) public view returns (bool) {
        bytes32 digest = _hashTypedData(structHash(a));
        (address signer, ECDSA.RecoverError err) = ECDSA.tryRecover(digest, sig);
        return (err == ECDSA.RecoverError.NoError) && (signer == a.grantor);
    }

    /// @notice Backwards-compatible entrypoint (no extra return tokens specified).
    function pull(Authorization calldata a, bytes calldata sig, uint256 amount, bytes calldata strategyData) external {
        address[] memory none = new address[](0);
        pull(a, sig, amount, strategyData, none);
    }

    /// @notice Execute a permissioned pull.
    /// @param returnTokens Optional list of extra tokens to sweep back to the grantor after strategy execution.
    ///        Include any tokens you expect the strategy to acquire (e.g., swap outputs). `tokenIn` is always swept.
    function pull(
        Authorization calldata a,
        bytes calldata sig,
        uint256 amount,
        bytes calldata strategyData,
        address[] memory returnTokens
    ) public nonReentrant {
        if (!verify(a, sig)) revert BAD_SIG();
        if (registry.revoked(a.grantor, a.nonce)) revert REVOKED();

        if (a.intervalSeconds == 0) revert BAD_INTERVAL();

        uint256 ts = block.timestamp;
        if (ts < a.validAfter) revert NOT_YET_VALID();
        if (ts > a.validBefore) revert EXPIRED();
        if (amount == 0 || amount > a.maxPerInterval) revert BAD_AMOUNT();

        (uint256 remaining, ) = registry.remainingBudget(_asReg(a));
        if (remaining == 0 || amount > remaining) revert NO_BUDGET();

        bytes32 h = authHash(a);
        IERC20 tokenIn = IERC20(a.tokenIn);

        tokenIn.safeTransferFrom(a.grantor, address(this), amount);
        emit Pulled(h, a.grantor, a.tokenIn, amount);

        // Track spend *after* funds are in executor (so a revert preserves user funds)
        registry.recordPull(_asReg(a), amount);

        // Strategy execution (untrusted external call) — guarded by nonReentrant.
        // If the strategy reverts, we revert the whole pull: funds remain with grantor (transferFrom already happened),
        // but will be rolled back by the revert as well.
        try IAthanorStrategy(a.strategy).execute(a.grantor, a.tokenIn, amount, strategyData) {
            // ok
        } catch {
            revert STRATEGY_FAILED();
        }

        // Always return tokenIn.
        _sweepToken(h, tokenIn, a.grantor);

        // Optionally return additional tokens produced by the strategy.
        // Duplicates are tolerated; zero/this/tokenIn are ignored.
        uint256 n = returnTokens.length;
        for (uint256 i = 0; i < n; i++) {
            address t = returnTokens[i];
            if (t == address(0) || t == address(tokenIn) || t == address(this)) continue;
            _sweepToken(h, IERC20(t), a.grantor);
        }

        // Return any ETH that might have been received (refunds, etc.).
        uint256 ethBal = address(this).balance;
        if (ethBal > 0) {
            (bool ok, ) = a.grantor.call{value: ethBal}("");
            if (!ok) revert ETH_RETURN_FAILED();
            emit Returned(h, a.grantor, address(0), ethBal);
        }
    }

    /// @dev Owner-only rescue (for accidental transfers). Not used in normal flow.
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
        emit Rescue(token, to, amount);
    }

    function rescueETH(address to, uint256 amount) external onlyOwner {
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert ETH_RETURN_FAILED();
        emit RescueETH(to, amount);
    }

    function _sweepToken(bytes32 h, IERC20 token, address to) internal {
        uint256 bal = token.balanceOf(address(this));
        if (bal > 0) {
            token.safeTransfer(to, bal);
            emit Returned(h, to, address(token), bal);
        } else {
            emit NoAction(h, "NO_RETURN_BALANCE");
        }
    }

    function _asReg(Authorization calldata a) internal pure returns (IAthanorConsentRegistry.Authorization calldata) {
        // same layout; solidity allows this cast in calldata via ABI compatibility
        return IAthanorConsentRegistry.Authorization(a);
    }

    receive() external payable {}
}
