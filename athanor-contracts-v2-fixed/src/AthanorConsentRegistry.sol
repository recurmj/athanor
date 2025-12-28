// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Ownable} from "./lib/Ownable.sol";

/// @notice Consent + budget registry for permissioned pull (Athanor).
/// @dev Responsibilities:
///  - nonce revocation (grantor-controlled)
///  - per-authorization rolling interval spend tracking (used to expose remaining budget)
///  - trusted executor gating for recordPull()
contract AthanorConsentRegistry is Ownable {
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

    event Revoked(address indexed grantor, bytes32 indexed nonce);
    event TrustedExecutorSet(address indexed executor, bool trusted);
    event PullRecorded(bytes32 indexed authHash, uint256 amount, uint256 windowStart, uint256 newSpent);

    error NotTrustedExecutor();
    error BadIntervalSeconds();

    mapping(address => mapping(bytes32 => bool)) public revoked; // grantor => nonce => revoked
    mapping(address => bool) public trustedExecutor;

    // authHash => interval window start (unix seconds rounded down)
    mapping(bytes32 => uint256) public windowStart;
    // authHash => spent in current window
    mapping(bytes32 => uint256) public spentInWindow;

    constructor() Ownable(msg.sender) {}

    /// @notice Grantor revokes an authorization nonce (invalidates all Authorizations with this nonce for this grantor).
    function revoke(bytes32 nonce) external {
        revoked[msg.sender][nonce] = true;
        emit Revoked(msg.sender, nonce);
    }

    /// @notice Governance/admin sets whether an executor is allowed to record pulls.
    function setTrustedExecutor(address executor, bool trusted) external onlyOwner {
        trustedExecutor[executor] = trusted;
        emit TrustedExecutorSet(executor, trusted);
    }

    function authHash(Authorization calldata a) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
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

    /// @notice Remaining budget for the current interval window.
    function remainingBudget(Authorization calldata a) external view returns (uint256 remaining, uint256 currentWindowStart) {
        if (a.intervalSeconds == 0) revert BadIntervalSeconds();

        bytes32 h = authHash(a);
        uint256 ts = block.timestamp;
        uint256 bucket = (ts / a.intervalSeconds) * a.intervalSeconds;
        uint256 spent = (windowStart[h] == bucket) ? spentInWindow[h] : 0;

        currentWindowStart = bucket;
        if (spent >= a.maxPerInterval) remaining = 0;
        else remaining = a.maxPerInterval - spent;
    }

    /// @notice Record a pull spend for the current window. Callable only by trusted executor.
    function recordPull(Authorization calldata a, uint256 amount) external {
        if (!trustedExecutor[msg.sender]) revert NotTrustedExecutor();
        if (a.intervalSeconds == 0) revert BadIntervalSeconds();

        bytes32 h = authHash(a);
        uint256 ts = block.timestamp;
        uint256 bucket = (ts / a.intervalSeconds) * a.intervalSeconds;

        if (windowStart[h] != bucket) {
            windowStart[h] = bucket;
            spentInWindow[h] = 0;
        }

        // We intentionally do NOT enforce maxPerInterval here; executor enforces it.
        // This function is for accounting only (trusted executor controlled).
        spentInWindow[h] += amount;

        emit PullRecorded(h, amount, bucket, spentInWindow[h]);
    }
}
