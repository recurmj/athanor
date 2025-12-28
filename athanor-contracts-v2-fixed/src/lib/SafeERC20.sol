// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "./IERC20.sol";

/// @notice Minimal SafeERC20 helper supporting non-standard ERC20s that return no bool.
library SafeERC20 {
    error SafeTransferFailed();
    error SafeTransferFromFailed();
    error SafeApproveFailed();

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, to, value));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFailed();
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeTransferFromFailed();
    }

    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        (bool ok, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, value));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert SafeApproveFailed();
    }
}
