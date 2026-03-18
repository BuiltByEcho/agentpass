export const REGISTRY_ABI = [
  {
    "type": "event",
    "name": "AgentRegistered",
    "inputs": [
      { "name": "agentId", "type": "uint256", "indexed": true },
      { "name": "wallet", "type": "address", "indexed": true }
    ]
  },
  {
    "type": "event",
    "name": "CredentialIssued",
    "inputs": [
      { "name": "agentWallet", "type": "address", "indexed": true },
      { "name": "scope", "type": "string", "indexed": false },
      { "name": "issuer", "type": "address", "indexed": true },
      { "name": "expiresAt", "type": "uint256", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "CredentialRevoked",
    "inputs": [
      { "name": "agentWallet", "type": "address", "indexed": true },
      { "name": "scope", "type": "string", "indexed": false },
      { "name": "issuer", "type": "address", "indexed": true }
    ]
  },
  {
    "type": "function",
    "name": "register",
    "inputs": [{ "name": "agentId", "type": "uint256" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "issueCredential",
    "inputs": [
      { "name": "agentWallet", "type": "address" },
      { "name": "scope", "type": "string" },
      { "name": "expiresAt", "type": "uint256" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "revokeCredential",
    "inputs": [
      { "name": "agentWallet", "type": "address" },
      { "name": "scope", "type": "string" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "hasCredential",
    "inputs": [
      { "name": "agentWallet", "type": "address" },
      { "name": "scope", "type": "string" }
    ],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getCredential",
    "inputs": [
      { "name": "agentWallet", "type": "address" },
      { "name": "scope", "type": "string" }
    ],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        { "name": "issuer", "type": "address" },
        { "name": "scope", "type": "string" },
        { "name": "issuedAt", "type": "uint256" },
        { "name": "expiresAt", "type": "uint256" },
        { "name": "revoked", "type": "bool" }
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAgentWallet",
    "inputs": [{ "name": "agentId", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "address" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getAgentId",
    "inputs": [{ "name": "wallet", "type": "address" }],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  }
] as const;

export const VERIFIER_ABI = [
  {
    "type": "function",
    "name": "verify",
    "inputs": [
      { "name": "agentId", "type": "uint256" },
      { "name": "service", "type": "string" },
      { "name": "nonce", "type": "string" },
      { "name": "timestamp", "type": "uint256" },
      { "name": "signature", "type": "bytes" }
    ],
    "outputs": [
      { "name": "valid", "type": "bool" },
      { "name": "agentWallet", "type": "address" },
      { "name": "returnedAgentId", "type": "uint256" }
    ],
    "stateMutability": "view"
  }
] as const;
