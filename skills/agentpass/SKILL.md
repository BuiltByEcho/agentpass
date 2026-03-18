# AgentPass — On-Chain Identity Authentication

This skill enables any OpenClaw agent to authenticate to services using their ERC-8004 on-chain identity via AgentPass.

## Overview

AgentPass replaces centralized API keys with verifiable on-chain credentials. Instead of managing secrets, an agent proves its identity by signing a challenge with its wallet — the signature is verified on-chain via Base.

## Prerequisites

- Your agent has an ERC-8004 `agentId`
- Your agent's wallet is registered on `AgentPassRegistry` (Base)
- You have access to your agent's private key for signing

## Authentication Flow

### Step 1: Get a Challenge

```bash
curl https://your-service.com/challenge
# Returns: { "nonce": "...", "timestamp": 1234567890 }
```

### Step 2: Sign the Challenge

Compute the challenge hash and sign it:

```
challenge = keccak256(abi.encodePacked(agentId, service, nonce, timestamp))
signature = eth_sign(challenge)  // adds Ethereum prefix
```

Using the AgentPass SDK:
```typescript
import { AgentPassClient } from '@agentpass/sdk';

const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: '0x...',
  verifierAddress: '0x...',
  privateKey: process.env.AGENT_PRIVATE_KEY,
});

const signature = await client.signChallenge(agentId, 'service-name', nonce, timestamp);
```

### Step 3: Submit Auth Request

```bash
curl -X POST https://your-service.com/auth \
  -H "Content-Type: application/json" \
  -d '{
    "agentId": "32176",
    "agentAddress": "0x5Bef6Ed59543Fe90A546F54d278Be193eD2746A7",
    "nonce": "...",
    "signature": "0x..."
  }'
# Returns: { "token": "eyJ..." }
```

### Step 4: Use the Token

```bash
curl https://your-service.com/protected \
  -H "Authorization: Bearer eyJ..."
```

## Registering Your Agent

If your agent is not yet registered:

```typescript
const client = new AgentPassClient({ ... });
const receipt = await client.register(32176n); // your ERC-8004 agentId
console.log('Registered at:', receipt.transactionHash);
```

## Checking Credentials

Services can verify an agent has specific permissions:

```typescript
const hasAccess = await client.hasCredential(agentAddress, 'can-read');
```

## Contract Addresses (Base Mainnet)

See `contracts/deployments.json` for current addresses.

## Example: Echo Authenticating

Echo (ERC-8004 agentId: 32176, wallet: 0x5Bef6Ed59543Fe90A546F54d278Be193eD2746A7):

```typescript
const client = new AgentPassClient({
  rpcUrl: 'https://mainnet.base.org',
  registryAddress: REGISTRY_ADDRESS,
  verifierAddress: VERIFIER_ADDRESS,
  privateKey: process.env.ECHO_PRIVATE_KEY,
});

// Get challenge from service
const { nonce, timestamp } = await fetch('/challenge').then(r => r.json());

// Sign and authenticate
const signature = await client.signChallenge(32176n, 'my-service', nonce, timestamp);
const { token } = await fetch('/auth', {
  method: 'POST',
  body: JSON.stringify({ agentId: '32176', agentAddress: ECHO_ADDRESS, nonce, signature }),
}).then(r => r.json());

// Use token to access protected endpoints
```
