import { createPublicClient, createWalletClient, http, encodeAbiParameters, keccak256, toBytes, type Address, type Hash, type WalletClient, type PublicClient, type Chain } from 'viem';
import { base } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import { REGISTRY_ABI, VERIFIER_ABI } from './abi.js';

export type { Address, Hash } from 'viem';
export { REGISTRY_ABI, VERIFIER_ABI } from './abi.js';

export interface AgentPassConfig {
  /** RPC URL for the chain (e.g., Base mainnet) */
  rpcUrl: string;
  /** Deployed AgentPassRegistry contract address */
  registryAddress: Address;
  /** Deployed AgentPassVerifier contract address */
  verifierAddress: Address;
  /** Private key hex string for signing transactions (optional for read-only) */
  privateKey?: `0x${string}`;
  /** Chain config — defaults to Base mainnet */
  chain?: Chain;
}

export interface Credential {
  issuer: Address;
  scope: string;
  issuedAt: bigint;
  expiresAt: bigint;
  revoked: boolean;
}

/**
 * AgentPassClient — interact with AgentPass on-chain identity system.
 * Supports agent registration, credential issuance, and challenge-based auth.
 */
export class AgentPassClient {
  private readonly publicClient: PublicClient;
  private readonly walletClient: WalletClient | null;
  private readonly registryAddress: Address;
  private readonly verifierAddress: Address;
  private readonly account: ReturnType<typeof privateKeyToAccount> | null;

  constructor(config: AgentPassConfig) {
    const chain = config.chain ?? base;

    this.registryAddress = config.registryAddress;
    this.verifierAddress = config.verifierAddress;

    this.publicClient = createPublicClient({
      chain,
      transport: http(config.rpcUrl),
    }) as PublicClient;

    if (config.privateKey) {
      this.account = privateKeyToAccount(config.privateKey);
      this.walletClient = createWalletClient({
        account: this.account,
        chain,
        transport: http(config.rpcUrl),
      });
    } else {
      this.account = null;
      this.walletClient = null;
    }
  }

  /** Get the wallet address for this client */
  get address(): Address | null {
    return this.account?.address ?? null;
  }

  /**
   * Register an ERC-8004 agent on-chain.
   * @param agentId — The agent's ERC-8004 identifier
   * @returns Transaction hash
   */
  async register(agentId: bigint): Promise<Hash> {
    this.assertWallet();
    return this.walletClient!.writeContract({
      address: this.registryAddress,
      abi: REGISTRY_ABI,
      functionName: 'register',
      args: [agentId],
      account: this.account!,
      chain: null,
    });
  }

  /**
   * Issue a scoped credential to an agent.
   * @param agentAddress — The agent's wallet address
   * @param scope — The credential scope (e.g., "can-read", "can-write")
   * @param expiresAt — Unix timestamp when credential expires (0 = never)
   * @returns Transaction hash
   */
  async issueCredential(
    agentAddress: Address,
    scope: string,
    expiresAt: number = 0,
  ): Promise<Hash> {
    this.assertWallet();
    return this.walletClient!.writeContract({
      address: this.registryAddress,
      abi: REGISTRY_ABI,
      functionName: 'issueCredential',
      args: [agentAddress, scope, BigInt(expiresAt)],
      account: this.account!,
      chain: null,
    });
  }

  /**
   * Check if an agent has a valid (non-expired, non-revoked) credential.
   */
  async hasCredential(agentAddress: Address, scope: string): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.registryAddress,
      abi: REGISTRY_ABI,
      functionName: 'hasCredential',
      args: [agentAddress, scope],
    }) as Promise<boolean>;
  }

  /**
   * Get full credential details for an agent.
   */
  async getCredential(agentAddress: Address, scope: string): Promise<Credential> {
    const result = await this.publicClient.readContract({
      address: this.registryAddress,
      abi: REGISTRY_ABI,
      functionName: 'getCredential',
      args: [agentAddress, scope],
    });
    return result as Credential;
  }

  /**
   * Get the wallet address for a registered agentId.
   */
  async getAgentWallet(agentId: bigint): Promise<Address> {
    return this.publicClient.readContract({
      address: this.registryAddress,
      abi: REGISTRY_ABI,
      functionName: 'getAgentWallet',
      args: [agentId],
    }) as Promise<Address>;
  }

  /**
   * Sign an auth challenge to prove agent identity.
   * The challenge is keccak256(abi.encode(agentId, service, nonce, timestamp)).
   * @param agentId — The agent's ERC-8004 identifier
   * @param service — The service requesting authentication
   * @param nonce — Unique nonce from the service
   * @param timestamp — Current Unix timestamp
   */
  async signChallenge(
    agentId: bigint,
    service: string,
    nonce: string,
    timestamp: number,
  ): Promise<`0x${string}`> {
    this.assertWallet();
    // Must match contract: keccak256(abi.encode(agentId, service, nonce, timestamp))
    const challenge = keccak256(
      encodeAbiParameters(
        [
          { name: 'agentId', type: 'uint256' },
          { name: 'service', type: 'string' },
          { name: 'nonce', type: 'string' },
          { name: 'timestamp', type: 'uint256' },
        ],
        [agentId, service, nonce, BigInt(timestamp)],
      ),
    );
    // Sign with eth_sign (adds Ethereum prefix)
    return this.account!.signMessage({
      message: { raw: toBytes(challenge) },
    });
  }

  /**
   * Verify a challenge signature on-chain.
   * @returns true if signature is valid, agent is registered, and timestamp is recent
   */
  async verifyChallenge(
    agentId: bigint,
    service: string,
    nonce: string,
    timestamp: number,
    signature: `0x${string}`,
  ): Promise<{ valid: boolean; agentWallet: Address; agentId: bigint }> {
    const [valid, agentWallet, returnedAgentId] = await this.publicClient.readContract({
      address: this.verifierAddress,
      abi: VERIFIER_ABI,
      functionName: 'verify',
      args: [agentId, service, nonce, BigInt(timestamp), signature],
    });
    return { valid, agentWallet, agentId: returnedAgentId };
  }

  private assertWallet(): void {
    if (!this.walletClient || !this.account) {
      throw new Error('AgentPassClient: privateKey required for write operations');
    }
  }
}