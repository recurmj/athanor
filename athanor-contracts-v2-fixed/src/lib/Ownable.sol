// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal Ownable (no OZ dependency).
abstract contract Ownable {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();

    address public owner;

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert NotOwner();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert NotOwner();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
