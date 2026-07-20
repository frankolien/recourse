import { createPublicClient, defineChain, http } from "viem";
import deployment from "../../deployments/arc-testnet.json";

export const arcTestnet = defineChain({
  id: deployment.chainId,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://arc-testnet.drpc.org"] },
  },
  blockExplorers: {
    default: { name: "ArcScan", url: "https://testnet.arcscan.app" },
  },
  testnet: true,
});

export const publicClient = createPublicClient({
  chain: arcTestnet,
  transport: http(),
});

export const escrowAddress = deployment.escrow as `0x${string}`;
export const registryAddress = deployment.policyRegistry as `0x${string}`;
export const vaultAddress = deployment.settlementVault as `0x${string}`;
export const yieldAdapterAddress = deployment.yieldAdapter as `0x${string}`;
export const usdcAddress = deployment.usdc as `0x${string}`;

const explorerBase = arcTestnet.blockExplorers.default.url;
export const explorerAddressUrl = (address: string) => `${explorerBase}/address/${address}`;
export const explorerTxUrl = (hash: string) => `${explorerBase}/tx/${hash}`;

const ruleComponents = [
  { name: "claimType", type: "uint8" },
  { name: "requiredEvidenceMask", type: "uint16" },
  { name: "attType", type: "uint8" },
  { name: "attExpected", type: "uint8" },
  { name: "claimWindow", type: "uint32" },
  { name: "refundBps", type: "uint16" },
  { name: "requiresReturn", type: "bool" },
] as const;

const verdictComponents = [
  { name: "refundBps", type: "uint16" },
  { name: "requiresReturn", type: "bool" },
  { name: "ruleIndex", type: "uint8" },
  { name: "matched", type: "bool" },
] as const;

export const escrowAbi = [
  {
    type: "function",
    name: "getPayment",
    stateMutability: "view",
    inputs: [{ name: "paymentId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "buyer", type: "address" },
          { name: "merchant", type: "address" },
          { name: "beneficiary", type: "address" },
          { name: "policyId", type: "uint256" },
          { name: "amount", type: "uint128" },
          { name: "shares", type: "uint128" },
          { name: "paidAt", type: "uint64" },
          { name: "filedAt", type: "uint64" },
          { name: "claimType", type: "uint8" },
          { name: "evidenceMask", type: "uint16" },
          { name: "attType", type: "uint8" },
          { name: "attValue", type: "uint8" },
          { name: "evidenceRoot", type: "bytes32" },
          { name: "verdictBps", type: "uint16" },
          { name: "status", type: "uint8" },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "previewVerdict",
    stateMutability: "view",
    inputs: [{ name: "paymentId", type: "uint256" }],
    outputs: [
      { name: "v", type: "tuple", components: verdictComponents },
      { name: "verdictHash", type: "bytes32" },
    ],
  },
] as const;

export const registryAbi = [
  {
    type: "function",
    name: "getPolicy",
    stateMutability: "view",
    inputs: [{ name: "policyId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "merchant", type: "address" },
          { name: "disputeWindow", type: "uint32" },
          { name: "defaultRefundBps", type: "uint16" },
          { name: "rules", type: "tuple[]", components: ruleComponents },
        ],
      },
    ],
  },
  {
    type: "function",
    name: "policyHash",
    stateMutability: "view",
    inputs: [{ name: "policyId", type: "uint256" }],
    outputs: [{ name: "", type: "bytes32" }],
  },
] as const;

export const explorerPaymentUrl = `${arcTestnet.blockExplorers.default.url}/address/${escrowAddress}`;
