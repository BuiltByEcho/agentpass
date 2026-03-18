// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AgentPassRegistry} from "./AgentPassRegistry.sol";

/// @title AgentPassVerifier
/// @notice Verifies agent identity proofs signed by AgentPass agent wallets.
/// @dev A proof is a secp256k1 signature over a challenge derived from
///      (agentId, service, nonce, timestamp). The verifier checks that:
///      1. The recovered signer matches the agent wallet stored in the registry.
///      2. The timestamp is within an acceptable window of block.timestamp.
///
///      Uses OpenZeppelin ECDSA to prevent signature malleability (high-s values).
///      Challenge encoding uses abi.encode to prevent hash collisions across
///      dynamic-length string fields.
contract AgentPassVerifier {
    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Maximum allowed age (and future drift) for a proof timestamp, in seconds.
    uint256 public constant TIMESTAMP_TOLERANCE = 300;

    /// @notice V value lower bound for normalisation (signatures may use 0/1 instead of 27/28).
    uint8 private constant V_LOWER = 27;

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
    ///      `keccak256(abi.encode(agentId, service, nonce, timestamp))`
    ///      wrapped with the Ethereum signed message prefix via OZ MessageHashUtils.
    ///
    ///      Uses OZ ECDSA.tryRecover which rejects high-s malleable signatures,
    ///      preventing replay via alternative valid signature forms.
    ///
    ///      Returns (false, address(0), 0) instead of reverting on any invalid
    ///      condition, so callers can branch on the boolean return value.
    ///
    ///      Note: block.timestamp is used intentionally for the time window check.
    ///      The 5-minute tolerance far exceeds the ~15 second miner manipulation
    ///      window, making timestamp grinding economically infeasible.
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
        // slither-disable-next-line timestamp
        if (!_timestampValid(timestamp)) {
            return (false, address(0), 0);
        }

        // ---- 2. Build challenge and recover signer ----------------------------
        // abi.encode pads each argument to 32 bytes, preventing the hash collision
        // that abi.encodePacked would allow across adjacent dynamic string fields.
        bytes32 challenge = keccak256(abi.encode(agentId, service, nonce, timestamp));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(challenge);

        // OZ ECDSA.tryRecover returns (address(0), error) for malformed or malleable sigs.
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(ethSignedHash, signature);
        if (err != ECDSA.RecoverError.NoError || recovered == address(0)) {
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

    /// @dev Returns true when `ts` is within TIMESTAMP_TOLERANCE of block.timestamp.
    ///      slither-disable-next-line timestamp — intentional use, tolerance >> miner drift.
    function _timestampValid(uint256 ts) private view returns (bool) {
        uint256 current = block.timestamp;
        if (ts > current + TIMESTAMP_TOLERANCE) return false;
        if (current > ts + TIMESTAMP_TOLERANCE) return false;
        return true;
    }
}
