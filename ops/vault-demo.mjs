// Exercises the SettlementVault end to end: enroll the merchant, LP-deposit, advance
// a Paid payment (merchant gets T+0 cash, vault takes the escrow claim), and, once
// the payment settles, reconcile. Run with --anvil against a fork first (R13): the
// fork run additionally warps past the dispute window, releases the escrow to the
// vault, reconciles, and asserts the share price rose.
//
//   node ops/vault-demo.mjs --rpc <url> [--anvil] [--reconcile-only]
//
// OWNER_PK must hold the vault owner key. Run from web/ so viem resolves.

import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, createTestClient, defineChain, erc20Abi, formatUnits, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name, fallback) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : fallback;
};

const RPC = opt("--rpc", "https://arc-testnet.drpc.org");
const PAYMENT_ID = BigInt(opt("--payment", "14"));
const FEE_BPS = 100; // 1% advance fee
const EXPOSURE_CAP = 50_000_000n; // 50 USDC
const LP_DEPOSIT = 4_000_000n; // 4 USDC so idle covers the net advance

const deployment = JSON.parse(readFileSync(new URL("../deployments/arc-testnet.json", import.meta.url)));

const chain = defineChain({
  id: deployment.chainId,
  name: "Arc",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [RPC] } },
});

const vaultAbi = parseAbi([
  "function totalAssets() view returns (uint256)",
  "function totalShares() view returns (uint256)",
  "function outstanding() view returns (uint256)",
  "function sharesOf(address) view returns (uint256)",
  "function convertToAssets(uint256) view returns (uint256)",
  "function merchants(address) view returns (bool enrolled, uint16 feeBps, uint128 exposureCap, uint128 exposure)",
  "function advances(uint256) view returns (address merchant, uint128 amount, bool exists, bool reconciled)",
  "function enrollMerchant(address merchant, uint16 feeBps, uint128 exposureCap)",
  "function deposit(uint256 assets) returns (uint256)",
  "function advance(uint256 paymentId)",
  "function reconcile(uint256 paymentId)",
]);

const escrowAbi = parseAbi([
  "function getPayment(uint256) view returns ((address buyer,address merchant,address beneficiary,uint256 policyId,uint128 amount,uint128 shares,uint64 paidAt,uint64 filedAt,uint8 claimType,uint16 evidenceMask,uint8 attType,uint8 attValue,bytes32 evidenceRoot,uint16 verdictBps,uint8 status))",
  "function release(uint256 paymentId)",
  "error WindowOpen()",
  "error NotOpen()",
]);

const ownerPk = process.env.OWNER_PK;
if (!ownerPk) throw new Error("OWNER_PK is required");
const owner = privateKeyToAccount(ownerPk);

const pub = createPublicClient({ chain, transport: http(RPC) });
const wallet = createWalletClient({ account: owner, chain, transport: http(RPC) });

const vault = deployment.settlementVault;
const escrow = deployment.escrow;
const usdc = deployment.usdc;

const fmt = (v) => `${formatUnits(v, 6)} USDC`;

async function state(label) {
  const [assets, shares, outstanding, payment, idle] = await Promise.all([
    pub.readContract({ address: vault, abi: vaultAbi, functionName: "totalAssets" }),
    pub.readContract({ address: vault, abi: vaultAbi, functionName: "totalShares" }),
    pub.readContract({ address: vault, abi: vaultAbi, functionName: "outstanding" }),
    pub.readContract({ address: escrow, abi: escrowAbi, functionName: "getPayment", args: [PAYMENT_ID] }),
    pub.readContract({ address: usdc, abi: erc20Abi, functionName: "balanceOf", args: [vault] }),
  ]);
  const merchant = payment.merchant;
  const merchantUsdc = await pub.readContract({ address: usdc, abi: erc20Abi, functionName: "balanceOf", args: [merchant] });
  const sharePrice = shares > 0n ? Number(assets) / Number(shares) : 1;
  console.log(`\n== ${label} ==`);
  console.log(`vault: assets ${fmt(assets)} (idle ${fmt(idle)}, outstanding ${fmt(outstanding)}), shares ${formatUnits(shares, 6)}, share price ${sharePrice.toFixed(6)}`);
  console.log(`payment #${PAYMENT_ID}: status ${payment.status}, amount ${fmt(payment.amount)}, beneficiary ${payment.beneficiary}`);
  console.log(`merchant ${merchant}: ${fmt(merchantUsdc)}`);
  return { assets, shares, outstanding, payment, merchantUsdc, sharePrice };
}

async function send(label, request) {
  const hash = await wallet.writeContract(request);
  const receipt = await pub.waitForTransactionReceipt({ hash });
  if (receipt.status !== "success") throw new Error(`${label} reverted: ${hash}`);
  console.log(`${label}: ${hash}`);
  return hash;
}

const before = await state("before");
const merchant = before.payment.merchant;

if (!flag("--reconcile-only")) {
  const terms = await pub.readContract({ address: vault, abi: vaultAbi, functionName: "merchants", args: [merchant] });
  if (!terms[0]) {
    await send("enrollMerchant", { address: vault, abi: vaultAbi, functionName: "enrollMerchant", args: [merchant, FEE_BPS, EXPOSURE_CAP] });
  } else {
    console.log("merchant already enrolled");
  }

  await send("approve", { address: usdc, abi: erc20Abi, functionName: "approve", args: [vault, LP_DEPOSIT] });
  await send("deposit", { address: vault, abi: vaultAbi, functionName: "deposit", args: [LP_DEPOSIT] });
  await send("advance", { address: vault, abi: vaultAbi, functionName: "advance", args: [PAYMENT_ID] });

  const after = await state("after advance");
  const gained = after.merchantUsdc - before.merchantUsdc;
  const expectedNet = (before.payment.amount * BigInt(10000 - FEE_BPS)) / 10000n;
  console.log(`\nmerchant received ${fmt(gained)} (expected net ${fmt(expectedNet)})`);
  if (gained !== expectedNet) throw new Error("net advance mismatch");
  if (after.payment.beneficiary.toLowerCase() !== vault.toLowerCase()) throw new Error("claim not assigned to vault");
}

if (flag("--anvil")) {
  // Fork-only: warp past the dispute window, release the escrow claim to the vault,
  // reconcile, and confirm LPs came out ahead (fee + float yield beat par).
  const test = createTestClient({ chain, mode: "anvil", transport: http(RPC) });
  await test.increaseTime({ seconds: 16 * 24 * 3600 });
  await test.mine({ blocks: 1 });
  await send("release", { address: escrow, abi: escrowAbi, functionName: "release", args: [PAYMENT_ID] });
  await send("reconcile", { address: vault, abi: vaultAbi, functionName: "reconcile", args: [PAYMENT_ID] });
  const settled = await state("after release + reconcile");
  // Pre-existing advances (payment 7 from seeding) stay outstanding until their own
  // windows elapse; only THIS advance must have cleared.
  if (settled.outstanding !== before.outstanding) throw new Error("outstanding did not return to its pre-advance level");
  if (settled.sharePrice <= 1.0) throw new Error("share price did not rise above par");
  console.log("\nANVIL DRY-RUN PASSED: advance, release, reconcile all correct; LPs up.");
}

if (flag("--reconcile-only")) {
  // Live settlement: after the dispute window nobody has called release() yet, so
  // this path must do it before the vault can reconcile. Status 1 = Paid (release
  // still needed), 3 = Settled (already released). Anything else means a dispute
  // is mid-flight and reconciling now would be wrong.
  if (before.payment.status === 1) {
    try {
      await pub.simulateContract({ address: escrow, abi: escrowAbi, functionName: "release", args: [PAYMENT_ID], account: owner });
    } catch (err) {
      throw new Error(`release() would revert (dispute window still open?): ${err.shortMessage ?? err.message}`);
    }
    await send("release", { address: escrow, abi: escrowAbi, functionName: "release", args: [PAYMENT_ID] });
  } else if (before.payment.status !== 3) {
    throw new Error(`payment #${PAYMENT_ID} is in status ${before.payment.status}; resolve the dispute before reconciling`);
  }

  const adv = await pub.readContract({ address: vault, abi: vaultAbi, functionName: "advances", args: [PAYMENT_ID] });
  if (!adv[2]) throw new Error(`no advance exists for payment #${PAYMENT_ID}; nothing to reconcile`);
  if (adv[3]) {
    console.log(`advance for payment #${PAYMENT_ID} already reconciled; nothing to do`);
  } else {
    await send("reconcile", { address: vault, abi: vaultAbi, functionName: "reconcile", args: [PAYMENT_ID] });
  }
  await state("after release + reconcile");
}
