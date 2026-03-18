// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentPassRegistry} from "../src/AgentPassRegistry.sol";

/// @title AgentPassRegistry Tests
/// @notice Unit tests covering registration, credential issuance, expiry, and revocation.
contract AgentPassRegistryTest is Test {
    AgentPassRegistry internal registry;

    // Convenient test addresses
    address internal constant AGENT_A = address(0xA1);
    address internal constant AGENT_B = address(0xB2);
    address internal constant AGENT_C = address(0xC3);

    uint256 internal constant AGENT_ID_A = 1;
    uint256 internal constant AGENT_ID_B = 2;

    string internal constant SCOPE_READ = "read";
    string internal constant SCOPE_WRITE = "write";

    function setUp() public {
        registry = new AgentPassRegistry();
    }

    // -------------------------------------------------------------------------
    // Registration
    // -------------------------------------------------------------------------

    /// @notice Registering an agent should persist wallet<->agentId mappings.
    function testRegister() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        assertEq(registry.getAgentWallet(AGENT_ID_A), AGENT_A, "wallet mismatch");
        assertEq(registry.getAgentId(AGENT_A), AGENT_ID_A, "agentId mismatch");
    }

    /// @notice Registering the same agentId twice should revert.
    function testRegisterDuplicateAgentId() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        vm.prank(AGENT_B);
        vm.expectRevert(
            abi.encodeWithSelector(AgentPassRegistry.AgentIdAlreadyRegistered.selector, AGENT_ID_A)
        );
        registry.register(AGENT_ID_A);
    }

    // -------------------------------------------------------------------------
    // Credential issuance
    // -------------------------------------------------------------------------

    /// @notice A registered agent can issue a credential; hasCredential returns true.
    function testIssueCredential() public {
        // Register issuer
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        // Register recipient
        vm.prank(AGENT_B);
        registry.register(AGENT_ID_B);

        // Issue credential from A to B
        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_B, SCOPE_READ, 0);

        assertTrue(registry.hasCredential(AGENT_B, SCOPE_READ), "should have credential");

        AgentPassRegistry.Credential memory cred = registry.getCredential(AGENT_B, SCOPE_READ);
        assertEq(cred.issuer, AGENT_A, "issuer mismatch");
        assertEq(cred.scope, SCOPE_READ, "scope mismatch");
        assertFalse(cred.revoked, "should not be revoked");
    }

    /// @notice An expired credential (expiresAt in the past) should not be valid.
    function testHasCredentialExpired() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        // Set a block timestamp and issue a credential that expires 1 second later.
        vm.warp(1_000_000);
        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_A, SCOPE_READ, block.timestamp + 1);

        // Advance time past expiry.
        vm.warp(block.timestamp + 10);
        assertFalse(registry.hasCredential(AGENT_A, SCOPE_READ), "expired credential should be invalid");
    }

    /// @notice A credential with expiresAt == 0 should never expire.
    function testHasCredentialNeverExpires() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_A, SCOPE_READ, 0);

        // Wind time forward by 100 years worth of seconds.
        vm.warp(block.timestamp + 365 days * 100);
        assertTrue(registry.hasCredential(AGENT_A, SCOPE_READ), "non-expiring credential should remain valid");
    }

    // -------------------------------------------------------------------------
    // Revocation
    // -------------------------------------------------------------------------

    /// @notice After revocation hasCredential should return false.
    function testRevokeCredential() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        vm.prank(AGENT_B);
        registry.register(AGENT_ID_B);

        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_B, SCOPE_READ, 0);

        assertTrue(registry.hasCredential(AGENT_B, SCOPE_READ), "pre-revoke: should have credential");

        vm.prank(AGENT_A);
        registry.revokeCredential(AGENT_B, SCOPE_READ);

        assertFalse(registry.hasCredential(AGENT_B, SCOPE_READ), "post-revoke: should not have credential");
    }

    /// @notice Only the original issuer may revoke a credential.
    function testRevokeUnauthorized() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        vm.prank(AGENT_B);
        registry.register(AGENT_ID_B);

        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_B, SCOPE_READ, 0);

        // AGENT_C tries to revoke — must revert.
        vm.prank(AGENT_C);
        vm.expectRevert(AgentPassRegistry.NotCredentialIssuer.selector);
        registry.revokeCredential(AGENT_B, SCOPE_READ);
    }

    /// @notice hasCredential returns false for a revoked credential.
    function testHasCredentialRevoked() public {
        vm.prank(AGENT_A);
        registry.register(AGENT_ID_A);

        vm.prank(AGENT_A);
        registry.issueCredential(AGENT_A, SCOPE_WRITE, 0);

        vm.prank(AGENT_A);
        registry.revokeCredential(AGENT_A, SCOPE_WRITE);

        AgentPassRegistry.Credential memory cred = registry.getCredential(AGENT_A, SCOPE_WRITE);
        assertTrue(cred.revoked, "revoked flag should be set");
        assertFalse(registry.hasCredential(AGENT_A, SCOPE_WRITE), "revoked credential should not be valid");
    }
}
