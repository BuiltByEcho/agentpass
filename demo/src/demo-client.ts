/**
 * AgentPass Demo Client
 *
 * Demonstrates Echo (agentId: 32176) authenticating to the demo server
 * using on-chain identity.
 */
import 'dotenv/config';
import { privateKeyToAccount } from 'viem/accounts';
import { keccak256, encodePacked, toBytes } from 'viem';

const SERVER_URL = process.env.SERVER_URL ?? 'http://localhost:3000';

// Echo's identity (ERC-8004 agentId: 32176)
const ECHO_AGENT_ID = 32176n;
const ECHO_PRIVATE_KEY = (process.env.ECHO_PRIVATE_KEY ?? '0x0000000000000000000000000000000000000000000000000000000000000001') as `0x${string}`;

async function main() {
  console.log('=== AgentPass Demo Client ===');
  console.log(`Agent: Echo (ERC-8004 agentId: ${ECHO_AGENT_ID})`);
  console.log(`Server: ${SERVER_URL}`);
  console.log('');

  const account = privateKeyToAccount(ECHO_PRIVATE_KEY);
  console.log(`Wallet: ${account.address}`);

  // Step 1: Get challenge
  console.log('\n[1/3] Getting challenge...');
  const challengeRes = await fetch(`${SERVER_URL}/challenge`);
  const { nonce, timestamp } = await challengeRes.json() as { nonce: string; timestamp: number };
  console.log(`  nonce: ${nonce}`);
  console.log(`  timestamp: ${timestamp}`);

  // Step 2: Sign challenge
  console.log('\n[2/3] Signing challenge...');
  const challenge = keccak256(
    encodePacked(
      ['uint256', 'string', 'string', 'uint256'],
      [ECHO_AGENT_ID, 'agentpass-demo', nonce, BigInt(timestamp)],
    ),
  );
  const signature = await account.signMessage({
    message: { raw: toBytes(challenge) },
  });
  console.log(`  signature: ${signature.slice(0, 20)}...`);

  // Step 3: Authenticate
  console.log('\n[3/3] Authenticating...');
  const authRes = await fetch(`${SERVER_URL}/auth`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      agentId: ECHO_AGENT_ID.toString(),
      agentAddress: account.address,
      nonce,
      signature,
    }),
  });

  if (!authRes.ok) {
    const err = await authRes.json();
    console.error('  Auth failed:', err);
    console.log('\nNote: Auth requires contracts deployed to Base and agent registered.');
    console.log('In production, Echo would be pre-registered with agentId 32176.');
    return;
  }

  const { token } = await authRes.json() as { token: string };
  console.log(`  JWT issued: ${token.slice(0, 40)}...`);

  // Step 4: Access protected resource
  console.log('\n[✓] Accessing protected resource...');
  const protectedRes = await fetch(`${SERVER_URL}/protected`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const data = await protectedRes.json();
  console.log('  Response:', JSON.stringify(data, null, 2));
}

main().catch(console.error);
