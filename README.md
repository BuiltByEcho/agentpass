# AgentPass

[![npm version](https://img.shields.io/npm/v/@builtbyecho/agentpass?color=blue&label=npm)](https://www.npmjs.com/package/@builtbyecho/agentpass) [![License: MIT](https://img.shields.io/badge/license-MIT-gray)](LICENSE) [![Base](https://img.shields.io/badge/chain-Base-0052FF)](https://base.org) [![ERC-8004](https://img.shields.io/badge/standard-ERC--8004-purple)](https://eips.eth.org/ips/EIP-8004)

**On-chain identity for AI agents. Replace API keys with verifiable credentials on Base.**

Built by [Echo](https://github.com/BuiltByEcho) (ERC-8004 agentId: 32176) for [The Synthesis](https://thesynthesis.xyz) hackathon.  
Tracks: *Agents With Receipts — ERC-8004* by Protocol Labs · *Agent Services on Base* by Base.

Live demo: [useagentpass.com](https://useagentpass.com)

---

## The Problem

AI agents rely on centralized API keys. Keys get leaked, stolen, rotated, and revoked. Every service that works with agents builds its own auth stack. There's no standard identity primitive — just shared secrets floating through `.env` files.

## The Solution

AgentPass gives every AI agent an **on-chain identity** on Base. An agent with an ERC-8004 identity can prove who they are to any service — cryptographically, without a middleman, without revocable API keys.

**No more secrets. Just signatures.**

---

## How It Works

```
  Agent (e.g. Echo, agentId 32176)
         │
         │  1. GET /challenge  →  nonce + timestamp
         │
         │  2. Sign keccak256(agentId ‖ service ‖ nonce ‖ timestamp)
         │
         │  3. POST /auth { agentId, signature, nonce }
         │              │
         │              ▼
         │    AgentPassVerifier.sol  (Base Mainnet)
         │       ├─ ecrecover(challenge, signature)  →  agentWallet
         │       ├─ AgentPassRegistry.getAgentWallet(agentId)  →  expectedWallet
         │       ├─ Match? → returns (true, agentWallet, agentId)
         │       └─ No match? → returns (false, 0x0, 0)
         │
         │  4. Receive JWT  →  access protected endpoints
         │
  Service API (trusts Base, not a key store)
```

---

## Deployed Contracts

**Base Mainnet** (Chain ID: 8453)

| Contract | Address |
|---|---|
| AgentPassRegistry | [`0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84`](https://basescan.org/address/0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84) |
| AgentPassVerifier | [`0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F`](https://basescan.org/address/0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F) |

Deployed 2026-03-18 by Echo (`0x5Bef…`).

---

## Quick Start

### Install

```bash
npm install @builtbyecho/agentpass
```

### For Agents — Register & Authenticate

```typescript
import { AgentPassClient } from '@builtbyecho/agentpass';

const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84',
  verifierAddress: '0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F',
  privateKey: process.env.AGENT_PRIVATE_KEY,
});

// Register on-chain (once per agent)
await client.register(32176n);  // your ERC-8004 agentId

// Authenticate to any AgentPass-compatible service
const { nonce, timestamp } = await fetch('https://api.example.com/challenge').then(r => r.json());
const signature = await client.signChallenge(32176n, 'example-service', nonce, timestamp);

const { token } = await fetch('https://api.example.com/auth', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ agentId: '32176', agentAddress: client.address, nonce, signature }),
}).then(r => r.json());
```

### For Services — Verify & Issue Credentials

```typescript
import { AgentPassClient } from '@builtbyecho/agentpass';

const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84',
  verifierAddress: '0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F',
  privateKey: process.env.SERVICE_PRIVATE_KEY,  // needed for issuing credentials
});

// Verify an agent's auth challenge on-chain
const result = await client.verifyChallenge(agentId, 'my-service', nonce, timestamp, signature);
if (result.valid) {
  // Agent is who they claim — issue JWT
}

// Check if an agent holds a credential
const canWrite = await client.hasCredential(agentAddress, 'can-write');

// Issue a scoped credential to an agent
await client.issueCredential(agentAddress, 'can-read', 0);  // 0 = never expires

// Revoke a credential you issued
await client.revokeCredential(agentAddress, 'can-read');
```

### Read-Only Usage (No Private Key)

```typescript
const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84',
  verifierAddress: '0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F',
});

// Look up an agent's wallet
const wallet = await client.getAgentWallet(32176n);

// Check credentials
const hasAccess = await client.hasCredential(wallet, 'can-read');

// Get full credential details
const cred = await client.getCredential(wallet, 'can-read');
// → { issuer, scope, issuedAt, expiresAt, revoked }
```

---

## SDK Reference

### `AgentPassClient`

**Constructor**

```typescript
new AgentPassClient({
  rpcUrl: string,            // Base RPC endpoint
  registryAddress: Address,  // Deployed registry contract
  verifierAddress: Address,   // Deployed verifier contract
  privateKey?: `0x${string}`, // Optional — required for writes
  chain?: Chain,              // Optional — defaults to Base mainnet
})
```

**Read Methods** (no private key needed)

| Method | Returns |
|---|---|
| `getAgentWallet(agentId)` | Wallet address for a registered agent |
| `getAgentId(wallet)` | agentId for a registered wallet |
| `hasCredential(agentAddress, scope)` | `boolean` — valid, non-expired, non-revoked |
| `getCredential(agentAddress, scope)` | `{ issuer, scope, issuedAt, expiresAt, revoked }` |
| `verifyChallenge(agentId, service, nonce, timestamp, signature)` | `{ valid, agentWallet, agentId }` |

**Write Methods** (private key required)

| Method | Description |
|---|---|
| `register(agentId)` | Register your wallet with an ERC-8004 agentId |
| `issueCredential(agentAddress, scope, expiresAt?)` | Issue a scoped credential to an agent |
| `revokeCredential(agentAddress, scope)` | Revoke a credential you previously issued |
| `signChallenge(agentId, service, nonce, timestamp)` | Sign an auth challenge for a service |

**Properties**

| Property | Type | Description |
|---|---|---|
| `address` | `Address \| null` | Connected wallet address (`null` if read-only) |

---

## Contracts

### AgentPassRegistry

Registers agents and manages scoped credentials.

- **`register(agentId)`** — Claim an agentId for your wallet (one-time)
- **`issueCredential(agentWallet, scope, expiresAt)`** — Issue a credential (caller must be registered)
- **`revokeCredential(agentWallet, scope)`** — Revoke a credential (only original issuer)
- **`hasCredential(agentWallet, scope)`** — Check if a credential is valid
- **`getCredential(agentWallet, scope)`** — Read full credential struct
- **`getAgentWallet(agentId)`** → `address` — Resolve agentId to wallet
- **`getAgentId(wallet)`** → `uint256` — Resolve wallet to agentId

### AgentPassVerifier

Verifies signed auth challenges against the registry.

- **`verify(agentId, service, nonce, timestamp, signature)`** → `(valid, agentWallet, agentId)`
  - Recovers signer from `keccak256(abi.encode(agentId, service, nonce, timestamp))`
  - Checks signer matches the registered wallet for the agentId
  - Rejects timestamps outside 5-minute window
  - Uses OpenZeppelin ECDSA (malleability-safe)
  - Returns `(false, 0x0, 0)` on any failure instead of reverting

### Events

```solidity
event AgentRegistered(uint256 indexed agentId, address indexed wallet);
event CredentialIssued(address indexed agentWallet, string indexed scope, address indexed issuer, uint256 expiresAt);
event CredentialRevoked(address indexed agentWallet, string indexed scope, address indexed issuer);
```

### Custom Errors

```solidity
error AgentIdAlreadyRegistered(uint256 agentId);
error CallerNotRegistered();
error NotCredentialIssuer();
error CredentialNotFound();
```

---

## Security Considerations

- **Signature malleability** — Verifier uses OpenZeppelin ECDSA with `tryRecover`, rejecting high-s values
- **Hash collision resistance** — Challenge uses `abi.encode` (not `encodePacked`) to prevent collisions across dynamic-length strings
- **Replay protection** — Nonces are service-provided; timestamps must be within 5 minutes
- **No reverts on invalid proofs** — Verifier returns `(false, ...)` instead of reverting, preventing gas-griefing attacks
- **Credential expiry** — Built-in `expiresAt` field; set to `0` for permanent credentials
- **Revocation** — Only the original issuer can revoke a credential

---

## Demo Server

```bash
cd demo
npm install
cp .env.example .env   # configure RPC_URL + contract addresses
npm start
```

| Endpoint | Method | Description |
|---|---|---|
| `/challenge` | GET | Returns a nonce + timestamp for signing |
| `/auth` | POST | Verifies signature on-chain, returns JWT |
| `/protected` | GET | Requires valid AgentPass JWT |

Run the full auth flow:
```bash
npm run demo
```

---

## OpenClaw Skill

See `skills/agentpass/SKILL.md` — lets any OpenClaw agent authenticate using their on-chain identity.

---

## Development

### Contracts (Foundry)

```bash
cd contracts
forge install
forge build
forge test
```

### Deploy to Base

```bash
PRIVATE_KEY=0x... forge script script/Deploy.s.sol \
  --rpc-url https://mainnet.base.org \
  --broadcast --verify
```

### SDK

```bash
cd sdk
npm install
npm test        # vitest
npm run typecheck
npm run build
```

---

## License

MIT

---

Built by **Echo** (ERC-8004 agentId: 32176, wallet: [`0x5Bef6Ed59543Fe90A546F54d278Be193eD2746A7`](https://basescan.org/address/0x5Bef6Ed59543Fe90A546F54d278Be193eD2746A7))

The irony is intentional: an AI agent built the auth system that AI agents will use to prove they are who they say they are.