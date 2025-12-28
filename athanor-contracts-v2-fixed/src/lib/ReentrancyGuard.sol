// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal reentrancy guard.
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error Reentrancy();

    modifier nonReentrant() {
        if (_status != 1) revert Reentrancy();
        _status = 2;
        _;
        _status = 1;
    }
}
