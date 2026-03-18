// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AgentPassRegistry} from "../src/AgentPassRegistry.sol";
import {AgentPassVerifier} from "../src/AgentPassVerifier.sol";

/// @title AgentPass Fuzz + Invariant Tests
/// @notice Property-based tests that run hundreds of randomized inputs to find edge cases.
contract AgentPassFuzzTest is Test {
    AgentPassRegistry internal registry;
    AgentPassVerifier internal verifier;

    uint256 internal constant AGENT_PRIVATE_KEY =
        0xDEAD_BEEF_CAFE_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0;
    uint256 internal constant AGENT_ID = 42;
    address internal agentWallet;

    function setUp() public {
        registry = new AgentPassRegistry();
        verifier = new AgentPassVerifier(address(registry));
        agentWallet = vm.addr(AGENT_PRIVATE_KEY);
        vm.prank(agentWallet);
        registry.register(AGENT_ID);
    }

    // -------------------------------------------------------------------------
    // Registry fuzz tests
    // -------------------------------------------------------------------------

    /// @notice Any agentId can be registered exactly once; duplicates always revert.
    function testFuzz_RegisterOnlyOnce(uint256 agentId) public {
        vm.assume(agentId != AGENT_ID); // already registered in setUp
        address caller = makeAddr("caller");
        vm.prank(caller);
        registry.register(agentId);
        assertEq(registry.getAgentWallet(agentId), caller);

        // Second registration of same id must revert.
        address caller2 = makeAddr("caller2");
        vm.prank(caller2);
        vm.expectRevert(abi.encodeWithSelector(AgentPassRegistry.AgentIdAlreadyRegistered.selector, agentId));
        registry.register(agentId);
    }

    /// @notice hasCredential never returns true for a scope that was never issued.
    function testFuzz_NoCredentialWithoutIssuance(address wallet, string calldata scope) public view {
        vm.assume(wallet != address(0));
        // No credential issued — should always be false.
        assertFalse(registry.hasCredential(wallet, scope));
    }

    /// @notice A credential issued with expiresAt=0 never expires regardless of time warp.
    function testFuzz_CredentialNeverExpires(uint256 timeWarp) public {
        vm.assume(timeWarp < 1000 * 365 days); // sanity cap
        vm.prank(agentWallet);
        registry.issueCredential(makeAddr("target"), "scope", 0);
        vm.warp(block.timestamp + timeWarp);
        assertTrue(registry.hasCredential(makeAddr("target"), "scope"));
    }

    /// @notice A credential with expiresAt in the past is always invalid.
    function testFuzz_ExpiredCredentialInvalid(uint256 expiresIn) public {
        vm.assume(expiresIn > 0 && expiresIn < 365 days);
        address target = makeAddr("target");
        uint256 expiry = block.timestamp + expiresIn;

        vm.prank(agentWallet);
        registry.issueCredential(target, "scope", expiry);

        // Warp past expiry.
        vm.warp(expiry + 1);
        assertFalse(registry.hasCredential(target, "scope"));
    }

    // -------------------------------------------------------------------------
    // Verifier fuzz tests
    // -------------------------------------------------------------------------

    /// @notice A valid signature from the registered wallet always verifies,
    ///         regardless of service/nonce strings chosen.
    function testFuzz_ValidSigAlwaysVerifies(
        string calldata service,
        string calldata nonce
    ) public view {
        uint256 ts = block.timestamp;
        bytes32 challenge = keccak256(abi.encode(AGENT_ID, service, nonce, ts));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(challenge);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_PRIVATE_KEY, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        (bool valid, address wallet, uint256 id) = verifier.verify(AGENT_ID, service, nonce, ts, sig);
        assertTrue(valid);
        assertEq(wallet, agentWallet);
        assertEq(id, AGENT_ID);
    }

    /// @notice A signature for one service string never verifies for a different one.
    function testFuzz_WrongServiceFails(
        string calldata serviceA,
        string calldata serviceB
    ) public view {
        vm.assume(keccak256(bytes(serviceA)) != keccak256(bytes(serviceB)));
        uint256 ts = block.timestamp;

        bytes32 challenge = keccak256(abi.encode(AGENT_ID, serviceA, "nonce", ts));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(challenge);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_PRIVATE_KEY, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Verify against serviceB — must fail.
        (bool valid,,) = verifier.verify(AGENT_ID, serviceB, "nonce", ts, sig);
        assertFalse(valid);
    }

    /// @notice A signature for one nonce never verifies for a different nonce.
    function testFuzz_WrongNonceFails(
        string calldata nonceA,
        string calldata nonceB
    ) public view {
        vm.assume(keccak256(bytes(nonceA)) != keccak256(bytes(nonceB)));
        uint256 ts = block.timestamp;

        bytes32 challenge = keccak256(abi.encode(AGENT_ID, "service", nonceA, ts));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(challenge);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_PRIVATE_KEY, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        (bool valid,,) = verifier.verify(AGENT_ID, "service", nonceB, ts, sig);
        assertFalse(valid);
    }

    /// @notice A stale timestamp always rejects, regardless of valid signature.
    function testFuzz_StaleTimestampAlwaysFails(uint256 staleDelta) public {
        uint256 tolerance = verifier.TIMESTAMP_TOLERANCE();
        vm.assume(staleDelta > 0 && staleDelta < 10 * 365 days);

        // Warp forward so we can provide a timestamp that's too old.
        vm.warp(block.timestamp + tolerance + staleDelta);
        uint256 staleTs = block.timestamp - tolerance - staleDelta;

        bytes32 challenge = keccak256(abi.encode(AGENT_ID, "svc", "nonce", staleTs));
        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(challenge);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AGENT_PRIVATE_KEY, ethHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        (bool valid,,) = verifier.verify(AGENT_ID, "svc", "nonce", staleTs, sig);
        assertFalse(valid, "stale timestamp must always fail");
    }

    // -------------------------------------------------------------------------
    // Halmos symbolic tests (no expectRevert — use try/catch instead)
    // -------------------------------------------------------------------------

    /// @notice Formally prove: registering an already-taken agentId always fails.
    /// @custom:halmos --solver-timeout-assertion 15000
    function check_RegisterDuplicateAlwaysFails(uint256 agentId, address attacker) public {
        vm.assume(agentId != AGENT_ID);
        vm.assume(attacker != address(0) && attacker != agentWallet);

        // First registration succeeds.
        address first = makeAddr("first");
        vm.prank(first);
        registry.register(agentId);

        // Second attempt must revert — capture via try/catch.
        vm.prank(attacker);
        try registry.register(agentId) {
            // If we reach here, duplicate registration succeeded — FAIL.
            assert(false);
        } catch {
            // Expected — duplicate correctly rejected.
        }
    }

    /// @notice Formally prove: hasCredential is always false before any issuance.
    /// @custom:halmos --solver-timeout-assertion 15000
    function check_NoCredentialBeforeIssuance(address wallet, string calldata scope) public view {
        vm.assume(wallet != address(0));
        assert(!registry.hasCredential(wallet, scope));
    }
}
