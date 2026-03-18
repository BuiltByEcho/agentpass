// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassRegistry} from "../src/AgentPassRegistry.sol";
import {AgentPassVerifier} from "../src/AgentPassVerifier.sol";

/// @title AgentPassVerifier Tests
/// @notice Unit tests covering valid signatures, expired timestamps, wrong signers,
///         and unregistered agents.
contract AgentPassVerifierTest is Test {
    AgentPassRegistry internal registry;
    AgentPassVerifier internal verifier;

    /// @dev Private key used to derive a deterministic test agent wallet.
    uint256 internal constant AGENT_PRIVATE_KEY = 0xDEAD_BEEF_CAFE_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0;
    uint256 internal constant OTHER_PRIVATE_KEY = 0xBAD_BAD_BAD_CAFE_DEAD_BEEF_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_1;

    uint256 internal constant AGENT_ID = 42;
    string  internal constant SERVICE  = "agentpass.example.com";
    string  internal constant NONCE    = "unique-nonce-abc123";

    address internal agentWallet;

    function setUp() public {
        registry = new AgentPassRegistry();
        verifier = new AgentPassVerifier(address(registry));

        // Derive the agent wallet from the private key and register it.
        agentWallet = vm.addr(AGENT_PRIVATE_KEY);
        vm.prank(agentWallet);
        registry.register(AGENT_ID);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// @dev Build the challenge hash exactly as AgentPassVerifier does.
    function _buildChallenge(
        uint256 agentId,
        string memory service,
        string memory nonce,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(agentId, service, nonce, timestamp));
    }

    /// @dev Wrap a raw hash with the Ethereum signed message prefix and sign it.
    function _sign(uint256 privateKey, bytes32 challenge)
        internal
        pure
        returns (bytes memory sig)
    {
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", challenge)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);
        sig = abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    /// @notice A correctly signed proof from the registered agent wallet must verify.
    function testVerifyValidSignature() public {
        uint256 ts = block.timestamp;
        bytes32 challenge = _buildChallenge(AGENT_ID, SERVICE, NONCE, ts);
        bytes memory sig = _sign(AGENT_PRIVATE_KEY, challenge);

        (bool valid, address wallet, uint256 returnedId) = verifier.verify(
            AGENT_ID, SERVICE, NONCE, ts, sig
        );

        assertTrue(valid, "proof should be valid");
        assertEq(wallet, agentWallet, "wallet mismatch");
        assertEq(returnedId, AGENT_ID, "agentId mismatch");
    }

    /// @notice A timestamp older than TIMESTAMP_TOLERANCE seconds returns false.
    function testVerifyExpiredTimestamp() public {
        uint256 tolerance = verifier.TIMESTAMP_TOLERANCE();

        // Warp to a later block so we can provide a stale timestamp.
        vm.warp(block.timestamp + tolerance + 1);

        uint256 staleTs = block.timestamp - tolerance - 1;
        bytes32 challenge = _buildChallenge(AGENT_ID, SERVICE, NONCE, staleTs);
        bytes memory sig = _sign(AGENT_PRIVATE_KEY, challenge);

        (bool valid, address wallet, uint256 returnedId) = verifier.verify(
            AGENT_ID, SERVICE, NONCE, staleTs, sig
        );

        assertFalse(valid, "expired timestamp should fail");
        assertEq(wallet, address(0), "wallet should be zero on failure");
        assertEq(returnedId, 0, "agentId should be 0 on failure");
    }

    /// @notice A proof signed by a different key than the registered wallet returns false.
    function testVerifyWrongSigner() public {
        uint256 ts = block.timestamp;
        bytes32 challenge = _buildChallenge(AGENT_ID, SERVICE, NONCE, ts);
        // Sign with a different key — recovered address will not match agentWallet.
        bytes memory sig = _sign(OTHER_PRIVATE_KEY, challenge);

        (bool valid, address wallet, uint256 returnedId) = verifier.verify(
            AGENT_ID, SERVICE, NONCE, ts, sig
        );

        assertFalse(valid, "wrong signer should fail");
        assertEq(wallet, address(0), "wallet should be zero on failure");
        assertEq(returnedId, 0, "agentId should be 0 on failure");
    }

    /// @notice Verifying an agentId that was never registered returns false.
    function testVerifyUnregisteredAgent() public {
        uint256 unregisteredId = 9999;
        uint256 ts = block.timestamp;
        bytes32 challenge = _buildChallenge(unregisteredId, SERVICE, NONCE, ts);
        bytes memory sig = _sign(AGENT_PRIVATE_KEY, challenge);

        (bool valid, address wallet, uint256 returnedId) = verifier.verify(
            unregisteredId, SERVICE, NONCE, ts, sig
        );

        assertFalse(valid, "unregistered agent should fail");
        assertEq(wallet, address(0), "wallet should be zero on failure");
        assertEq(returnedId, 0, "agentId should be 0 on failure");
    }
}
