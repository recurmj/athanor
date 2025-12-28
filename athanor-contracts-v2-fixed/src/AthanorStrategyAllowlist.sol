// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAthanorStrategy} from "./IAthanorStrategy.sol";
import {Ownable} from "./lib/Ownable.sol";

/// @notice Strategy adapter that can perform *allowlisted* external calls.
/// @dev Owner can update allowlist; executor is the only caller of execute().
///      **Proof Mode**: if `data.length == 0`, this strategy performs a NO-OP (pure return).
contract AthanorStrategyAllowlist is IAthanorStrategy, Ownable {
    event AllowlistSet(address indexed target, bool allowed);
    event ExecutorSet(address indexed executor);
    event Called(address indexed target, uint256 value, bytes4 selector);
    event Noop();

    error NotExecutor();
    error TargetNotAllowed();
    error ExternalCallFailed();
    error ValueNotAllowed();

    address public executor;
    mapping(address => bool) public allowed;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setExecutor(address _executor) external onlyOwner {
        executor = _executor;
        emit ExecutorSet(_executor);
    }

    function setAllowed(address target, bool isAllowed) external onlyOwner {
        allowed[target] = isAllowed;
        emit AllowlistSet(target, isAllowed);
    }

    /// @notice data encoding: abi.encode(target, value, callData)
    /// @dev If `data.length == 0`, this is a NO-OP (used for Proof Mode pure return).
    function execute(address, address, uint256, bytes calldata data) external override {
        if (msg.sender != executor) revert NotExecutor();

        if (data.length == 0) {
            emit Noop();
            return;
        }

        (address target, uint256 value, bytes memory callData) = abi.decode(data, (address, uint256, bytes));
        if (!allowed[target]) revert TargetNotAllowed();
        if (value != 0) revert ValueNotAllowed();

        bytes4 sel = callData.length >= 4 ? bytes4(callData[0:4]) : bytes4(0);
        (bool ok, ) = target.call(callData);
        if (!ok) revert ExternalCallFailed();

        emit Called(target, value, sel);
    }

    // Accept ETH refunds only; strategy execution does not forward ETH (value forced to 0).
    receive() external payable {}
}
