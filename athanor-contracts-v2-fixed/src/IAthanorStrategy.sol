// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAthanorStrategy {
    /// @notice Execute with `amountIn` of `tokenIn` currently held by the executor.
    /// @dev Must return tokenIn back to executor (plus any profit) before returning.
    function execute(address grantor, address tokenIn, uint256 amountIn, bytes calldata data) external;
}
