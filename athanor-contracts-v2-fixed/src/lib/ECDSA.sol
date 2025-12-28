// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Minimal ECDSA helpers with low-s enforcement.
library ECDSA {
    error InvalidSignature();
    error InvalidSignatureLength();
    error InvalidSignatureS();
    error InvalidSignatureV();

    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV
    }

    uint256 internal constant _SECP256K1N_HALF =
        0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    function recover(bytes32 digest, bytes memory signature) internal pure returns (address) {
        (address signer, RecoverError err) = tryRecover(digest, signature);
        if (err == RecoverError.InvalidSignatureLength) revert InvalidSignatureLength();
        if (err == RecoverError.InvalidSignatureS) revert InvalidSignatureS();
        if (err == RecoverError.InvalidSignatureV) revert InvalidSignatureV();
        if (err != RecoverError.NoError) revert InvalidSignature();
        return signer;
    }

    function tryRecover(bytes32 digest, bytes memory signature)
        internal
        pure
        returns (address signer, RecoverError err)
    {
        if (signature.length != 65) return (address(0), RecoverError.InvalidSignatureLength);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (uint256(s) > _SECP256K1N_HALF) return (address(0), RecoverError.InvalidSignatureS);
        if (v != 27 && v != 28) return (address(0), RecoverError.InvalidSignatureV);

        signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) return (address(0), RecoverError.InvalidSignature);
        return (signer, RecoverError.NoError);
    }
}
