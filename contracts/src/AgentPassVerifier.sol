// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentPassRegistry} from "./AgentPassRegistry.sol";

/// @title AgentPassVerifier
/// @notice Verifies agent identity proofs signed by AgentPass agent wallets.
/// @dev A proof is a secp256k1 signature over a challenge derived from
///      (agentId, service, nonce, timestamp). The verifier checks that:
///      1. The recovered signer matches the agent wallet stored in the registry.
///      2. The timestamp is within an acceptable window of block.timestamp.
///
///      Signature encoding follows the standard Ethereum personal_sign / eth_sign
///      convention: the hash is prefixed with "\x19Ethereum Signed Message:\n32"
///      before the ecrecover call, matching the output of `eth_sign` RPC calls and
///      common wallet libraries.
contract AgentPassVerifier {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Maximum allowed age (and future drift) for a proof timestamp, in seconds.
    uint256 public constant TIMESTAMP_TOLERANCE = 300;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    /// @notice The AgentPassRegistry this verifier consults for agent wallet lookups.
    AgentPassRegistry public immutable registry;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param registry_ Address of the deployed AgentPassRegistry contract.
    constructor(address registry_) {
        registry = AgentPassRegistry(registry_);
    }

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /// @notice Verify an agent's signed proof of identity.
    /// @dev The challenge hash is:
    ///      `keccak256(abi.encodePacked(agentId, service, nonce, timestamp))`
    ///      wrapped with the Ethereum signed message prefix before ecrecover.
    ///
    ///      Returns (false, address(0), 0) instead of reverting on any invalid
    ///      condition, so callers can branch on the boolean return value.
    ///
    /// @param agentId   The numeric identifier claimed by the agent.
    /// @param service   Identifier of the service being accessed (arbitrary string).
    /// @param nonce     Unique string to prevent replay attacks.
    /// @param timestamp Unix timestamp at which the agent created the proof.
    /// @param signature 65-byte secp256k1 signature (r ++ s ++ v).
    /// @return valid           True if the proof is authentic and timely.
    /// @return agentWallet     The wallet address of the verified agent (address(0) if invalid).
    /// @return returnedAgentId The agentId echoed back (0 if invalid).
    function verify(
        uint256 agentId,
        string calldata service,
        string calldata nonce,
        uint256 timestamp,
        bytes calldata signature
    )
        external
        view
        returns (
            bool valid,
            address agentWallet,
            uint256 returnedAgentId
        )
    {
        // ---- 1. Timestamp window check ----------------------------------------
        if (!_timestampValid(timestamp)) {
            return (false, address(0), 0);
        }

        // ---- 2. Build challenge and recover signer ----------------------------
        // Use abi.encode (not encodePacked) to prevent hash collisions between
        // dynamic-length fields (service, nonce). encodePacked("ab","cdef") ==
        // encodePacked("abc","def"), which would allow forged challenges.
        bytes32 challenge = keccak256(abi.encode(agentId, service, nonce, timestamp));
        address recovered = _recoverSigner(challenge, signature);
        if (recovered == address(0)) {
            return (false, address(0), 0);
        }

        // ---- 3. Registry lookup ----------------------------------------------
        address expectedWallet = registry.getAgentWallet(agentId);
        if (expectedWallet == address(0)) {
            return (false, address(0), 0);
        }

        // ---- 4. Signer match -------------------------------------------------
        if (recovered != expectedWallet) {
            return (false, address(0), 0);
        }

        return (true, expectedWallet, agentId);
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /// @dev Returns true when `timestamp` is within TIMESTAMP_TOLERANCE of block.timestamp.
    function _timestampValid(uint256 timestamp) private view returns (bool) {
        uint256 current = block.timestamp;
        if (timestamp > current + TIMESTAMP_TOLERANCE) return false;
        if (current > timestamp + TIMESTAMP_TOLERANCE) return false;
        return true;
    }

    /// @dev Recovers the signer of `challenge` from a 65-byte (r, s, v) `signature`.
    ///      Applies the Ethereum signed message prefix before calling ecrecover.
    ///      Returns address(0) on any failure (bad length, invalid v, ecrecover failure).
    function _recoverSigner(bytes32 challenge, bytes calldata signature)
        private
        pure
        returns (address)
    {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            // v is encoded as the last byte.
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        // Normalise v from {0,1} to {27,28} when signers omit the offset.
        if (v < 27) {
            v += 27;
        }

        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", challenge)
        );

        return ecrecover(ethSignedHash, v, r, s);
    }
}
