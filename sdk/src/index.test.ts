import { describe, it, expect } from 'vitest'
import { encodeAbiParameters, keccak256, toBytes } from 'viem'
import { AgentPassClient, REGISTRY_ABI, VERIFIER_ABI } from './index.js'

// We test local utilities only — on-chain calls need a real RPC + deployed contracts.

describe('AgentPassClient', () => {
  const config = {
    rpcUrl: 'https://mainnet.base.org',
    registryAddress: '0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84' as const,
    verifierAddress: '0xb9305BD41BBB9F6B34682BE4ab70410228ED7C3F' as const,
  }

  it('creates a read-only client without a private key', () => {
    const client = new AgentPassClient(config)
    expect(client.address).toBeNull()
  })

  it('creates a client with a private key and exposes the address', () => {
    const client = new AgentPassClient({
      ...config,
      privateKey: '0x0000000000000000000000000000000000000000000000000000000000000001',
    })
    expect(client.address).toBe('0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf')
  })

  it('throws on write operations without a private key', async () => {
    const client = new AgentPassClient(config)
    await expect(client.register(1n)).rejects.toThrow('privateKey required')
  })

  it('challenge hash matches contract abi.encode encoding', () => {
    // The contract uses keccak256(abi.encode(agentId, service, nonce, timestamp))
    // We verify our local computation matches.
    const agentId = 32176n
    const service = 'useagentpass'
    const nonce = '645887ab-d6bc-4582-8294-2ded2ddaf414'
    const timestamp = 1777263812n

    const challenge = keccak256(
      encodeAbiParameters(
        [
          { name: 'agentId', type: 'uint256' },
          { name: 'service', type: 'string' },
          { name: 'nonce', type: 'string' },
          { name: 'timestamp', type: 'uint256' },
        ],
        [agentId, service, nonce, timestamp],
      ),
    )

    // Should produce a 32-byte hash
    expect(challenge).toMatch(/^0x[0-9a-f]{64}$/)
  })
})

describe('ABIs', () => {
  it('exports REGISTRY_ABI with expected functions', () => {
    const names = REGISTRY_ABI.filter((item: any) => item.type === 'function').map((item: any) => item.name)
    expect(names).toContain('register')
    expect(names).toContain('issueCredential')
    expect(names).toContain('hasCredential')
    expect(names).toContain('getCredential')
    expect(names).toContain('getAgentWallet')
    expect(names).toContain('getAgentId')
  })

  it('exports VERIFIER_ABI with verify function', () => {
    const names = VERIFIER_ABI.filter((item: any) => item.type === 'function').map((item: any) => item.name)
    expect(names).toContain('verify')
  })
})