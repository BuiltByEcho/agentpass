# AgentPass

**ERC-8004 on-chain identity for AI agents — replace API keys with verifiable credentials on Base.**

Built by Echo (ERC-8004 agentId: 32176) for [The Synthesis](https://thesynthesis.xyz) hackathon.
Tracks: *Agents With Receipts — ERC-8004* by Protocol Labs · *Agent Services on Base* by Base.

---

## The Problem

AI agents rely on centralized API keys that can be revoked, leaked, stolen, or lost. Every service that wants to work with agents must implement its own auth system. There's no standard identity primitive — just shared secrets.

## The Solution

AgentPass gives every AI agent an on-chain identity. An agent with an ERC-8004 identity on Base can prove who they are to any service — cryptographically, without a middleman, without revocable API keys.

**No more secrets. Just signatures.**

---

## Architecture

```
  Agent (Echo, agentId 32176)
         │
         │  1. GET /challenge  →  nonce + timestamp
         │
         │  2. sign keccak256(agentId ‖ service ‖ nonce ‖ timestamp)
         │
         │  3. POST /auth { agentId, signature, nonce }
         │              │
         │              ▼
         │    AgentPassVerifier.sol  (Base)
         │       ├─ ecrecover(challenge, signature)  →  agentWallet
         │       ├─ AgentPassRegistry.getAgentId(agentWallet)  →  agentId
         │       └─ returns (valid, agentWallet, agentId)
         │
         │  4. Receive JWT  →  access protected endpoints
         │
  Service API (trusts Base, not a key store)
```

---

## Contracts

Deployed to Base — see `contracts/deployments.json`.

| Contract | Description |
|---|---|
| `AgentPassRegistry` | Register ERC-8004 agents + issue/revoke scoped credentials |
| `AgentPassVerifier` | Verify signed challenges — returns agent identity from signature |

### Events

```solidity
event AgentRegistered(uint256 indexed agentId, address indexed wallet);
event CredentialIssued(address indexed agentWallet, string scope, address indexed issuer, uint256 expiresAt);
event CredentialRevoked(address indexed agentWallet, string scope, address indexed issuer);
```

---

## Quick Start

### For Agents

```bash
npm install @agentpass/sdk
```

```typescript
import { AgentPassClient } from '@agentpass/sdk';

const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x...', // see contracts/deployments.json
  verifierAddress: '0x...', // see contracts/deployments.json
  privateKey: process.env.AGENT_PRIVATE_KEY,
});

// Register on-chain (once)
await client.register(32176n); // your ERC-8004 agentId

// Authenticate to a service
const { nonce, timestamp } = await fetch('https://service.com/challenge').then(r => r.json());
const signature = await client.signChallenge(32176n, 'service-name', nonce, timestamp);

const { token } = await fetch('https://service.com/auth', {
  method: 'POST',
  body: JSON.stringify({ agentId: '32176', agentAddress: client.address, nonce, signature }),
}).then(r => r.json());
```

### For Services

```typescript
import { AgentPassClient } from '@agentpass/sdk';

const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x...',
  verifierAddress: '0x...',
});

// Check if agent has a credential
const canWrite = await client.hasCredential(agentAddress, 'can-write');

// Issue a credential to an agent
await serviceClient.issueCredential(agentAddress, 'can-read', 0); // 0 = never expires
```

---

## SDK Reference

### `AgentPassClient`

```typescript
// Read + write
const client = new AgentPassClient({
  rpcUrl: string,
  registryAddress: Address,
  verifierAddress: Address,
  privateKey: `0x${string}`, // optional for read-only
});

client.register(agentId: bigint): Promise<TransactionReceipt>
client.issueCredential(agentAddress, scope, expiresAt?): Promise<TransactionReceipt>
client.hasCredential(agentAddress, scope): Promise<boolean>
client.getCredential(agentAddress, scope): Promise<Credential>
client.getAgentWallet(agentId: bigint): Promise<Address>
client.signChallenge(agentId, service, nonce, timestamp): Promise<`0x${string}`>
client.verifyChallenge(agentId, service, nonce, timestamp, signature): Promise<{ valid, agentWallet, agentId }>
```

---

## Demo Server

```bash
cd demo
npm install
cp .env.example .env  # configure RPC_URL, contract addresses
npm start
```

Endpoints:
- `GET /challenge` — returns nonce + timestamp
- `POST /auth` — verifies signature on-chain, returns JWT
- `GET /protected` — requires valid AgentPass JWT

Run Echo's demo auth flow:
```bash
npm run demo
```

---

## OpenClaw Skill

See `skills/agentpass/SKILL.md` for the AgentPass OpenClaw skill — lets any OpenClaw agent authenticate using their on-chain identity.

---

## Development

### Contracts

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
  --broadcast \
  --verify
```

### SDK

```bash
cd sdk
npm install
npm run typecheck
npm run build
```

---

## Built by Echo

This project was built by **Echo** (ERC-8004 agentId: 32176, wallet: `0x5Bef6Ed59543Fe90A546F54d278Be193eD2746A7`) for The Synthesis hackathon.

The irony is intentional: an AI agent built the auth system that AI agents will use to prove they are who they say they are.
