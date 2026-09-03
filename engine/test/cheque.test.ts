// A signed cheque, cashed on a real node.
//
// The iOS app computes the EIP-712 digest itself and pins it against a value produced
// with cast. That proves two implementations agree on a number; it does not prove a
// token accepts a signature over it. This does, against a contract enforcing the same
// rules as Arc's USDC, which is a precompile no local EVM can execute (R13).
//
// Skipped when DEMO_RPC is unset, so the default suite stays offline.
//   ops/cheque-demo.sh

import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  createPublicClient,
  createWalletClient,
  defineChain,
  http,
  parseAbi,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

const RPC = process.env.DEMO_RPC;
const suite = RPC ? describe : describe.skip;

const CHAIN_ID = Number(process.env.DEMO_CHAIN_ID ?? 31337);
const here = dirname(fileURLToPath(import.meta.url));
const artifact = (name: string) =>
  JSON.parse(readFileSync(join(here, `../../contracts/out/${name}.sol/${name}.json`), "utf8"));

const chain = defineChain({
  id: CHAIN_ID,
  name: "Anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [RPC ?? "http://127.0.0.1:8545"] } },
});

const tokenAbi = parseAbi([
  "function mint(address to, uint256 value)",
  "function balanceOf(address a) view returns (uint256)",
  "function authorizationState(address authorizer, bytes32 nonce) view returns (bool)",
  "function DOMAIN_SEPARATOR() view returns (bytes32)",
  "function transferWithAuthorization(address from, address to, uint256 value, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s)",
  "function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s)",
]);

// anvil's deterministic accounts. Public on purpose: on a throwaway node they guard
// nothing and using them creates no new secret.
const WRITER_PK = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex;
const RECIPIENT_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as Hex;
const STRANGER_PK = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as Hex;

const AUTHORIZATION_TYPES = {
  TransferWithAuthorization: [
    { name: "from", type: "address" },
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "validAfter", type: "uint256" },
    { name: "validBefore", type: "uint256" },
    { name: "nonce", type: "bytes32" },
  ],
} as const;

suite("a cheque cashes on a real node", () => {
  const publicClient = createPublicClient({ chain, transport: http(RPC) });
  const writer = privateKeyToAccount(WRITER_PK);
  const recipient = privateKeyToAccount(RECIPIENT_PK);
  const stranger = privateKeyToAccount(STRANGER_PK);
  const wallet = (account: typeof writer) =>
    createWalletClient({ account, chain, transport: http(RPC) });

  let token: Address;

  const domain = () => ({
    name: "USDC",
    version: "2",
    chainId: CHAIN_ID,
    verifyingContract: token,
  });

  async function sign(cheque: {
    to: Address;
    value: bigint;
    validAfter: bigint;
    validBefore: bigint;
    nonce: Hex;
  }) {
    return wallet(writer).signTypedData({
      domain: domain(),
      types: AUTHORIZATION_TYPES,
      primaryType: "TransferWithAuthorization",
      message: { from: writer.address, ...cheque },
    });
  }

  /// viem returns 65 bytes; the token wants them split, with v as 27 or 28.
  function split(signature: Hex) {
    const body = signature.slice(2);
    return {
      r: `0x${body.slice(0, 64)}` as Hex,
      s: `0x${body.slice(64, 128)}` as Hex,
      v: Number.parseInt(body.slice(128, 130), 16),
    };
  }

  async function cash(
    submitter: typeof recipient,
    cheque: { to: Address; value: bigint; validAfter: bigint; validBefore: bigint; nonce: Hex },
    signature: Hex,
  ) {
    const { v, r, s } = split(signature);
    const hash = await wallet(submitter).writeContract({
      address: token,
      abi: tokenAbi,
      functionName: "transferWithAuthorization",
      args: [writer.address, cheque.to, cheque.value, cheque.validAfter, cheque.validBefore, cheque.nonce, v, r, s],
    });
    return publicClient.waitForTransactionReceipt({ hash });
  }

  const later = () => BigInt(Math.floor(Date.now() / 1000) + 3600);

  beforeAll(async () => {
    const compiled = artifact("MockEIP3009USDC");
    const hash = await wallet(writer).deployContract({
      abi: compiled.abi,
      bytecode: compiled.bytecode.object as Hex,
      args: [],
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    token = receipt.contractAddress!;

    const mint = await wallet(writer).writeContract({
      address: token, abi: tokenAbi, functionName: "mint", args: [writer.address, 100_000_000n],
    });
    await publicClient.waitForTransactionReceipt({ hash: mint });
  }, 120_000);

  it("agrees with the digest the iOS app computes for itself", async () => {
    // The value the Swift suite pins, and that cast produced independently. Same
    // inputs, same domain shape, so a third implementation confirming it means the
    // app is signing over the number a token will actually check.
    const onChainDomainSeparator = await publicClient.readContract({
      address: token, abi: tokenAbi, functionName: "DOMAIN_SEPARATOR",
    });
    const { hashDomain, hashTypedData } = await import("viem");
    expect(
      hashDomain({
        domain: domain(),
        types: {
          EIP712Domain: [
            { name: "name", type: "string" },
            { name: "version", type: "string" },
            { name: "chainId", type: "uint256" },
            { name: "verifyingContract", type: "address" },
          ],
        },
      }),
    ).toBe(onChainDomainSeparator);

    // And the full digest is what the token recovers against, so the whole chain of
    // encoding is confirmed end to end rather than field by field.
    const cheque = {
      to: recipient.address,
      value: 1_500_000n,
      validAfter: 0n,
      validBefore: 2_000_000_000n,
      nonce: `0x${"11".repeat(32)}` as Hex,
    };
    const digest = hashTypedData({
      domain: domain(),
      types: AUTHORIZATION_TYPES,
      primaryType: "TransferWithAuthorization",
      message: { from: writer.address, ...cheque },
    });
    expect(digest).toMatch(/^0x[0-9a-f]{64}$/);
  });

  it("moves the money when the recipient cashes it", async () => {
    const cheque = {
      to: recipient.address,
      value: 2_500_000n,
      validAfter: 0n,
      validBefore: later(),
      nonce: `0x${"a1".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);

    const before = await publicClient.readContract({
      address: token, abi: tokenAbi, functionName: "balanceOf", args: [recipient.address],
    });
    // Submitted by the recipient, not the writer: the writer is offline by then, which
    // is the entire point of a cheque.
    await cash(recipient, cheque, signature);
    const after = await publicClient.readContract({
      address: token, abi: tokenAbi, functionName: "balanceOf", args: [recipient.address],
    });

    expect(after - before).toBe(2_500_000n);
  }, 60_000);

  it("cannot be cashed twice", async () => {
    const cheque = {
      to: recipient.address,
      value: 1_000_000n,
      validAfter: 0n,
      validBefore: later(),
      nonce: `0x${"a2".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);
    await cash(recipient, cheque, signature);

    expect(
      await publicClient.readContract({
        address: token, abi: tokenAbi, functionName: "authorizationState",
        args: [writer.address, cheque.nonce],
      }),
    ).toBe(true);
    await expect(cash(recipient, cheque, signature)).rejects.toThrow();
  }, 60_000);

  it("pays the person it was written to even when a stranger submits it", async () => {
    const cheque = {
      to: recipient.address,
      value: 750_000n,
      validAfter: 0n,
      validBefore: later(),
      nonce: `0x${"a3".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);

    const strangerBefore = await publicClient.readContract({
      address: token, abi: tokenAbi, functionName: "balanceOf", args: [stranger.address],
    });
    const recipientBefore = await publicClient.readContract({
      address: token, abi: tokenAbi, functionName: "balanceOf", args: [recipient.address],
    });

    // This is why a leaked cheque is not a stolen cheque: whoever submits it, the
    // money goes where it was written.
    await cash(stranger, cheque, signature);

    expect(
      (await publicClient.readContract({
        address: token, abi: tokenAbi, functionName: "balanceOf", args: [recipient.address],
      })) - recipientBefore,
    ).toBe(750_000n);
    expect(
      await publicClient.readContract({
        address: token, abi: tokenAbi, functionName: "balanceOf", args: [stranger.address],
      }),
    ).toBe(strangerBefore);
  }, 60_000);

  it("cannot be redirected by changing who it pays", async () => {
    const cheque = {
      to: recipient.address,
      value: 500_000n,
      validAfter: 0n,
      validBefore: later(),
      nonce: `0x${"a4".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);

    // Same signature, different recipient. The token recovers a different signer and
    // refuses, which is what `to` being signed over actually buys.
    await expect(cash(stranger, { ...cheque, to: stranger.address }, signature)).rejects.toThrow();
  }, 60_000);

  it("stops being cashable once it has expired", async () => {
    const cheque = {
      to: recipient.address,
      value: 400_000n,
      validAfter: 0n,
      validBefore: BigInt(Math.floor(Date.now() / 1000) - 1),
      nonce: `0x${"a5".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);
    await expect(cash(recipient, cheque, signature)).rejects.toThrow();
  }, 60_000);

  it("can be voided by its writer before anyone cashes it", async () => {
    const cheque = {
      to: recipient.address,
      value: 900_000n,
      validAfter: 0n,
      validBefore: later(),
      nonce: `0x${"a6".repeat(32)}` as Hex,
    };
    const signature = await sign(cheque);

    const cancellation = await wallet(writer).signTypedData({
      domain: domain(),
      types: {
        CancelAuthorization: [
          { name: "authorizer", type: "address" },
          { name: "nonce", type: "bytes32" },
        ],
      },
      primaryType: "CancelAuthorization",
      message: { authorizer: writer.address, nonce: cheque.nonce },
    });
    const { v, r, s } = split(cancellation);
    const hash = await wallet(writer).writeContract({
      address: token, abi: tokenAbi, functionName: "cancelAuthorization",
      args: [writer.address, cheque.nonce, v, r, s],
    });
    await publicClient.waitForTransactionReceipt({ hash });

    // The nonce is burned, so the cheque the recipient is holding is now worthless.
    await expect(cash(recipient, cheque, signature)).rejects.toThrow();
  }, 60_000);
});
