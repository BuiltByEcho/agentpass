// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentPassRegistry
/// @notice Registry for AgentPass agent identities and verifiable credentials.
/// @dev Agents register their wallet address against a numeric agentId. Registered agents
///      can issue scoped credentials to other agent wallets. Credentials can be revoked by
///      their original issuer and optionally carry an expiry timestamp.
contract AgentPassRegistry {
    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /// @notice Represents a verifiable credential tied to an agent wallet and scope.
    struct Credential {
        /// @notice Address of the agent that issued this credential.
        address issuer;
        /// @notice The scope (capability / permission label) this credential grants.
        string scope;
        /// @notice Block timestamp at which the credential was issued.
        uint256 issuedAt;
        /// @notice Block timestamp after which the credential is considered expired.
        ///         A value of 0 means the credential never expires.
        uint256 expiresAt;
        /// @notice Whether the issuer has revoked this credential.
        bool revoked;
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Maps agentId to the wallet address that registered it.
    mapping(uint256 agentId => address wallet) private _agentIdToWallet;

    /// @notice Maps a wallet address to the agentId it registered.
    mapping(address wallet => uint256 agentId) private _walletToAgentId;

    /// @notice Tracks which agentIds have been registered (needed to distinguish agentId 0).
    mapping(uint256 agentId => bool registered) private _agentIdRegistered;

    /// @notice Stores credentials keyed by agent wallet and scope string.
    mapping(address agent => mapping(string scope => Credential)) private _credentials;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new agent is registered.
    /// @param agentId The numeric identifier chosen by the agent.
    /// @param wallet  The wallet address that was registered.
    event AgentRegistered(uint256 indexed agentId, address indexed wallet);

    /// @notice Emitted when a credential is issued to an agent wallet.
    /// @param agentWallet The wallet that received the credential.
    /// @param scope       The scope of the credential.
    /// @param issuer      The agent wallet that issued the credential.
    /// @param expiresAt   Expiry timestamp (0 = never expires).
    event CredentialIssued(
        address indexed agentWallet,
        string scope,
        address indexed issuer,
        uint256 expiresAt
    );

    /// @notice Emitted when a credential is revoked.
    /// @param agentWallet The wallet whose credential was revoked.
    /// @param scope       The scope of the revoked credential.
    /// @param issuer      The agent wallet that performed the revocation.
    event CredentialRevoked(
        address indexed agentWallet,
        string scope,
        address indexed issuer
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when an agentId is already registered.
    error AgentIdAlreadyRegistered(uint256 agentId);

    /// @notice Thrown when the caller is not a registered agent.
    error CallerNotRegistered();

    /// @notice Thrown when the caller is not the original issuer of a credential.
    error NotCredentialIssuer();

    /// @notice Thrown when attempting to revoke a credential that does not exist.
    error CredentialNotFound();

    // -------------------------------------------------------------------------
    // External functions
    // -------------------------------------------------------------------------

    /// @notice Register the caller's address with the given agentId.
    /// @dev Reverts if the agentId is already taken. A wallet can only hold one agentId;
    ///      calling again with a different agentId will overwrite the wallet mapping but
    ///      the old agentId remains registered, so prefer treating registration as one-time.
    /// @param agentId The numeric identifier the caller wishes to claim.
    function register(uint256 agentId) external {
        if (_agentIdRegistered[agentId]) {
            revert AgentIdAlreadyRegistered(agentId);
        }
        _agentIdRegistered[agentId] = true;
        _agentIdToWallet[agentId] = msg.sender;
        _walletToAgentId[msg.sender] = agentId;
        emit AgentRegistered(agentId, msg.sender);
    }

    /// @notice Issue a scoped credential to an agent wallet.
    /// @dev The caller must be a registered agent. Overwrites any existing credential for
    ///      the same (agentWallet, scope) pair.
    /// @param agentWallet The recipient agent's wallet address.
    /// @param scope       The capability / permission label.
    /// @param expiresAt   Expiry timestamp in seconds (0 = never expires).
    function issueCredential(
        address agentWallet,
        string calldata scope,
        uint256 expiresAt
    ) external {
        if (_walletToAgentId[msg.sender] == 0 && !_agentIdRegistered[0]) {
            // Caller has agentId 0 but 0 was never explicitly registered — not a real agent.
            revert CallerNotRegistered();
        }
        // More precise check: the caller must have a registered agentId entry.
        if (_agentIdToWallet[_walletToAgentId[msg.sender]] != msg.sender) {
            revert CallerNotRegistered();
        }

        _credentials[agentWallet][scope] = Credential({
            issuer: msg.sender,
            scope: scope,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            revoked: false
        });

        emit CredentialIssued(agentWallet, scope, msg.sender, expiresAt);
    }

    /// @notice Revoke a credential previously issued by the caller.
    /// @dev Only the original issuer of the credential may revoke it.
    /// @param agentWallet The agent wallet holding the credential.
    /// @param scope       The scope of the credential to revoke.
    function revokeCredential(address agentWallet, string calldata scope) external {
        Credential storage cred = _credentials[agentWallet][scope];
        if (cred.issuer == address(0)) {
            revert CredentialNotFound();
        }
        if (cred.issuer != msg.sender) {
            revert NotCredentialIssuer();
        }
        cred.revoked = true;
        emit CredentialRevoked(agentWallet, scope, msg.sender);
    }

    /// @notice Check whether an agent wallet currently holds a valid credential for a scope.
    /// @dev Returns false if the credential does not exist, has been revoked, or has expired.
    ///      An expiresAt of 0 is treated as "never expires".
    /// @param agentWallet The agent wallet to query.
    /// @param scope       The scope to check.
    /// @return True if the credential is present, not revoked, and not expired.
    function hasCredential(address agentWallet, string calldata scope)
        external
        view
        returns (bool)
    {
        Credential storage cred = _credentials[agentWallet][scope];
        if (cred.issuer == address(0)) return false;
        if (cred.revoked) return false;
        if (cred.expiresAt != 0 && block.timestamp > cred.expiresAt) return false;
        return true;
    }

    /// @notice Retrieve the full credential struct for a given agent wallet and scope.
    /// @param agentWallet The agent wallet to query.
    /// @param scope       The scope of the credential.
    /// @return The `Credential` struct (issuer will be address(0) if not found).
    function getCredential(address agentWallet, string calldata scope)
        external
        view
        returns (Credential memory)
    {
        return _credentials[agentWallet][scope];
    }

    /// @notice Look up the wallet address registered for a given agentId.
    /// @param agentId The agentId to query.
    /// @return The wallet address, or address(0) if not registered.
    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _agentIdToWallet[agentId];
    }

    /// @notice Look up the agentId registered by a given wallet address.
    /// @param wallet The wallet address to query.
    /// @return The agentId, or 0 if not registered (note: 0 may also be a valid agentId).
    function getAgentId(address wallet) external view returns (uint256) {
        return _walletToAgentId[wallet];
    }
}
