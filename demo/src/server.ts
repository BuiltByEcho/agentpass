import 'dotenv/config';
import express, { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { createPublicClient, http, keccak256, encodePacked, toBytes, type Address } from 'viem';
import { base } from 'viem/chains';
import crypto from 'crypto';

const app = express();
app.use(express.json());

const JWT_SECRET = process.env.JWT_SECRET ?? 'agentpass-demo-secret-change-in-prod';
const RPC_URL = process.env.RPC_URL ?? 'https://mainnet.base.org';
const REGISTRY_ADDRESS = (process.env.REGISTRY_ADDRESS ?? '0x0000000000000000000000000000000000000000') as Address;
const VERIFIER_ADDRESS = (process.env.VERIFIER_ADDRESS ?? '0x0000000000000000000000000000000000000000') as Address;

// In-memory nonce store (use Redis in production)
const pendingChallenges = new Map<string, { timestamp: number; expiresAt: number }>();

const publicClient = createPublicClient({
  chain: base,
  transport: http(RPC_URL),
});

const VERIFIER_ABI = [
  {
    type: 'function' as const,
    name: 'verify',
    inputs: [
      { name: 'agentId', type: 'uint256' as const },
      { name: 'service', type: 'string' as const },
      { name: 'nonce', type: 'string' as const },
      { name: 'timestamp', type: 'uint256' as const },
      { name: 'signature', type: 'bytes' as const },
    ],
    outputs: [
      { name: 'valid', type: 'bool' as const },
      { name: 'agentWallet', type: 'address' as const },
      { name: 'returnedAgentId', type: 'uint256' as const },
    ],
    stateMutability: 'view' as const,
  },
] as const;

/**
 * GET /challenge
 * Returns a nonce + timestamp for an agent to sign.
 */
app.get('/challenge', (_req: Request, res: Response) => {
  const nonce = crypto.randomUUID();
  const timestamp = Math.floor(Date.now() / 1000);
  const expiresAt = timestamp + 300; // 5 minute window

  pendingChallenges.set(nonce, { timestamp, expiresAt });

  // Clean up expired challenges
  for (const [n, c] of pendingChallenges) {
    if (c.expiresAt < timestamp) pendingChallenges.delete(n);
  }

  res.json({ nonce, timestamp, expiresAt });
});

/**
 * POST /auth
 * Accepts agentId + agentAddress + nonce + signature, verifies on-chain, returns JWT.
 */
app.post('/auth', async (req: Request, res: Response) => {
  try {
    const { agentId, agentAddress, nonce, signature } = req.body as {
      agentId: string;
      agentAddress: string;
      nonce: string;
      signature: string;
    };

    if (!agentId || !agentAddress || !nonce || !signature) {
      res.status(400).json({ error: 'Missing required fields: agentId, agentAddress, nonce, signature' });
      return;
    }

    const challenge = pendingChallenges.get(nonce);
    if (!challenge) {
      res.status(401).json({ error: 'Invalid or expired nonce' });
      return;
    }

    const now = Math.floor(Date.now() / 1000);
    if (challenge.expiresAt < now) {
      pendingChallenges.delete(nonce);
      res.status(401).json({ error: 'Challenge expired' });
      return;
    }

    // Verify on-chain
    const [valid, , returnedAgentId] = await publicClient.readContract({
      address: VERIFIER_ADDRESS,
      abi: VERIFIER_ABI,
      functionName: 'verify',
      args: [
        BigInt(agentId),
        'agentpass-demo',
        nonce,
        BigInt(challenge.timestamp),
        signature as `0x${string}`,
      ],
    });

    if (!valid) {
      res.status(401).json({ error: 'Invalid signature or unregistered agent' });
      return;
    }

    // Consume nonce
    pendingChallenges.delete(nonce);

    // Issue JWT
    const token = jwt.sign(
      {
        agentId: returnedAgentId.toString(),
        agentAddress,
        iss: 'agentpass-demo',
      },
      JWT_SECRET,
      { expiresIn: '1h' },
    );

    res.json({
      token,
      agentId: returnedAgentId.toString(),
      agentAddress,
      expiresIn: 3600,
    });
  } catch (err) {
    console.error('Auth error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * Middleware: verify AgentPass JWT
 */
function requireAgentPass(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing Authorization header' });
    return;
  }

  const token = authHeader.slice(7);
  try {
    const payload = jwt.verify(token, JWT_SECRET) as { agentId: string; agentAddress: string };
    (req as Request & { agent: typeof payload }).agent = payload;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

/**
 * GET /protected
 * Requires a valid AgentPass JWT.
 */
app.get('/protected', requireAgentPass, (req: Request, res: Response) => {
  const agent = (req as Request & { agent: { agentId: string; agentAddress: string } }).agent;
  res.json({
    message: '🔐 Access granted. You have proven your on-chain identity.',
    agent: {
      agentId: agent.agentId,
      agentAddress: agent.agentAddress,
    },
    secret: 'The answer to life, the universe, and everything is 42.',
    timestamp: new Date().toISOString(),
  });
});

const PORT = parseInt(process.env.PORT ?? '3000', 10);
app.listen(PORT, () => {
  console.log(`AgentPass demo server running on http://localhost:${PORT}`);
  console.log('  GET  /challenge  — get a nonce to sign');
  console.log('  POST /auth       — authenticate with signature');
  console.log('  GET  /protected  — access protected resource');
});
