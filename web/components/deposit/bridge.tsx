"use client";

/**
 * Moving USDC onto Arc from a chain the person already keeps money on.
 *
 * The burn is signed by their own wallet and names their Recourse account as the
 * recipient, so nobody, this page included, ever holds the money in between. The
 * mint on Arc is left to Circle's forwarder, which is why there is only one
 * signature and no need for gas on a chain they have never used.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { getAddress, isAddress } from "viem";
import { useAccount, useConnect, useReadContract, useSwitchChain, useWriteContract } from "wagmi";
import {
  ARC_DOMAIN,
  FAST_FINALITY,
  FORWARDING_HOOK,
  SOURCE_CHAINS,
  TOKEN_MESSENGER,
  asBytes32,
  erc20Abi,
  fetchAttestation,
  fetchFee,
  formatUsdc,
  maxFeeFor,
  parseUsdc,
  tokenMessengerAbi,
  type FeeQuote,
  type SourceChain,
} from "@/lib/cctp";

type Phase = "form" | "approving" | "burning" | "waiting" | "done";

/** Below this the forwarding fee is a visible share of the deposit. */
const MINIMUM = 1_000_000n;

export function BridgeDeposit() {
  const params = useSearchParams();
  // Checked for shape rather than for checksum casing: the address arrives from
  // the app, and rejecting a real account over a capital letter would strand it.
  const given = params.get("to");
  const valid = given ? isAddress(given, { strict: false }) : false;
  const destination = valid ? getAddress(given!) : null;

  const { address, isConnected, chainId } = useAccount();
  const { connect, connectors, isPending: connecting } = useConnect();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync } = useWriteContract();

  const [source, setSource] = useState<SourceChain>(SOURCE_CHAINS[0]);
  const [amount, setAmount] = useState("");
  const [phase, setPhase] = useState<Phase>("form");
  const [error, setError] = useState<string | null>(null);
  const [burnTx, setBurnTx] = useState<string | null>(null);
  const [arcTx, setArcTx] = useState<string | null>(null);
  const [quote, setQuote] = useState<FeeQuote | null>(null);
  const [slow, setSlow] = useState(false);

  const units = useMemo(() => parseUsdc(amount), [amount]);

  const { data: balance } = useReadContract({
    address: source.usdc,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    chainId: source.chain.id,
    query: { enabled: Boolean(address), refetchInterval: 15_000 },
  });

  // Fees are quoted per chain and move, so they are read when the chain changes
  // rather than at build time.
  useEffect(() => {
    let live = true;
    setQuote(null);
    fetchFee(source.domain)
      .then((value) => live && setQuote(value))
      .catch(() => live && setQuote(null));
    return () => {
      live = false;
    };
  }, [source]);

  // Circle indexes the burn a moment after it lands, and the forwarder finishes
  // once the attestation is signed. Both are polled from here.
  useEffect(() => {
    if (phase !== "waiting" || !burnTx) return;
    let live = true;
    const started = Date.now();
    const timer = setInterval(async () => {
      const answer = await fetchAttestation(source.domain, burnTx);
      if (!live) return;
      if (answer?.forwardTxHash) {
        setArcTx(answer.forwardTxHash);
        setPhase("done");
        return;
      }
      if (answer?.delayReason === "insufficient_fee" || Date.now() - started > 120_000) setSlow(true);
    }, 3_000);
    return () => {
      live = false;
      clearInterval(timer);
    };
  }, [phase, burnTx, source.domain]);

  const insufficient = units !== null && balance !== undefined && units > balance;
  const belowMinimum = units !== null && units > 0n && units < MINIMUM;
  const ready = valid && isConnected && units !== null && units > 0n && !insufficient && !belowMinimum && quote !== null;

  const deposit = useCallback(async () => {
    if (!ready || !units || !quote || !destination) return;
    setError(null);
    try {
      if (chainId !== source.chain.id) await switchChainAsync({ chainId: source.chain.id });

      // Approving the exact amount rather than an unlimited allowance: this is a
      // wallet the person also uses elsewhere, and a standing approval on it is a
      // cost they did not ask to carry.
      setPhase("approving");
      await writeContractAsync({
        address: source.usdc,
        abi: erc20Abi,
        functionName: "approve",
        args: [TOKEN_MESSENGER, units],
        chainId: source.chain.id,
      });

      setPhase("burning");
      const hash = await writeContractAsync({
        address: TOKEN_MESSENGER,
        abi: tokenMessengerAbi,
        functionName: "depositForBurnWithHook",
        args: [
          units,
          ARC_DOMAIN,
          asBytes32(destination),
          source.usdc,
          // Left open on purpose: anyone may complete the mint, which is what
          // lets Circle's forwarder do it, and lets us finish a stuck one.
          `0x${"0".repeat(64)}`,
          maxFeeFor(units, quote),
          FAST_FINALITY,
          FORWARDING_HOOK,
        ],
        chainId: source.chain.id,
      });
      setBurnTx(hash);
      setPhase("waiting");
    } catch (cause) {
      setPhase("form");
      setError(describe(cause));
    }
  }, [ready, units, quote, destination, chainId, source, switchChainAsync, writeContractAsync]);

  if (!valid) {
    return (
      <main className="dep-wrap">
        <Header />
        <p className="dep-note">Open this page from the Recourse app, so it knows which account to pay.</p>
      </main>
    );
  }

  if (phase === "done") {
    return (
      <main className="dep-wrap">
        <Header />
        <div className="dep-done">
          <div className="dep-tick" aria-hidden="true" />
          <h2>{formatUsdc(units ?? 0n)} USDC is on Arc</h2>
          <p>It is in your Recourse balance now. You can close this page.</p>
          {arcTx ? (
            <a className="dep-link" href={`https://testnet.arcscan.app/tx/${arcTx}`} target="_blank" rel="noreferrer">
              See it on ArcScan
            </a>
          ) : null}
        </div>
      </main>
    );
  }

  if (phase === "waiting") {
    return (
      <main className="dep-wrap">
        <Header />
        <div className="dep-done">
          <div className="dep-spin" aria-hidden="true" />
          <h2>Bringing it across</h2>
          <p>
            {slow
              ? "This one is taking the slow route and can take about fifteen minutes. The money is not lost, and it lands without you here."
              : `Circle is signing for the transfer and finishing it on Arc. About ${source.seconds} seconds.`}
          </p>
          <p className="dep-fine">You can close this page. It arrives either way.</p>
        </div>
      </main>
    );
  }

  const busy = phase === "approving" || phase === "burning";

  return (
    <main className="dep-wrap">
      <Header />

      <p className="dep-to">
        To your account <span>{short(destination!)}</span>
      </p>

      <div className="dep-field">
        <span className="dep-label">From</span>
        <div className="dep-chains">
          {SOURCE_CHAINS.map((option) => (
            <button
              key={option.key}
              type="button"
              className={`dep-chain${option.key === source.key ? " is-on" : ""}`}
              onClick={() => setSource(option)}
              disabled={busy}
            >
              {option.name}
            </button>
          ))}
        </div>
      </div>

      <div className="dep-field">
        <div className="dep-label-row">
          <span className="dep-label">Amount</span>
          {balance !== undefined ? (
            <button type="button" className="dep-max" onClick={() => setAmount(formatUsdc(balance))} disabled={busy}>
              {formatUsdc(balance)} available
            </button>
          ) : null}
        </div>
        <div className="dep-amount">
          <input
            inputMode="decimal"
            placeholder="0.00"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            disabled={busy}
            aria-label="Amount in USDC"
          />
          <span>USDC</span>
        </div>
      </div>

      {isConnected ? (
        <>
          <dl className="dep-summary">
            <div>
              <dt>Route</dt>
              <dd>Circle CCTP</dd>
            </div>
            <div>
              <dt>Fee</dt>
              <dd>{quote && units ? `${formatUsdc(maxFeeFor(units, quote))} USDC at most` : "Checking"}</dd>
            </div>
            <div>
              <dt>Arrives as</dt>
              <dd>USDC on Arc</dd>
            </div>
          </dl>

          <button type="button" className="dep-go" onClick={deposit} disabled={!ready || busy}>
            {phase === "approving" ? "Approve in your wallet" : phase === "burning" ? "Confirm in your wallet" : "Deposit"}
          </button>

          {insufficient ? <p className="dep-error">You do not have that much USDC on {source.name}.</p> : null}
          {belowMinimum ? <p className="dep-error">The smallest deposit is 1 USDC.</p> : null}
          {error ? <p className="dep-error">{error}</p> : null}
        </>
      ) : (
        <Connect connect={connect} connectors={connectors} connecting={connecting} />
      )}

      <p className="dep-fine">
        Your wallet signs once, on {source.name}. The money is burned there and minted on Arc by Circle, straight to your account. Nobody holds it in
        between.
      </p>
    </main>
  );
}

function Header() {
  return (
    <header className="dep-head">
      <h1>Add money from another chain</h1>
      <p>USDC you already hold, moved to Arc through Circle&apos;s own bridge.</p>
    </header>
  );
}

type ConnectProps = {
  connect: ReturnType<typeof useConnect>["connect"];
  connectors: ReturnType<typeof useConnect>["connectors"];
  connecting: boolean;
};

function Connect({ connect, connectors, connecting }: ConnectProps) {
  // wagmi always offers the generic injected connector, whether or not a wallet
  // put anything in the page, so the page asks the window itself.
  const [hasWallet, setHasWallet] = useState(false);
  const [phone, setPhone] = useState(false);
  useEffect(() => {
    setHasWallet("ethereum" in window);
    setPhone(/iphone|ipad|android/i.test(navigator.userAgent));
  }, []);

  const named = connectors.filter((connector) => connector.id !== "injected");
  const list = named.length ? named : connectors;
  const bare = list.length === 0 || (named.length === 0 && !hasWallet);

  if (bare) return <HandOff phone={phone} />;

  return (
    <div className="dep-connect">
      {list.map((connector) => (
        <button key={connector.uid} type="button" className="dep-go" onClick={() => connect({ connector })} disabled={connecting}>
          {connecting ? "Opening your wallet" : connector.id === "injected" ? "Connect wallet" : `Connect ${connector.name}`}
        </button>
      ))}
    </div>
  );
}

/**
 * No wallet can reach a page in Safari, in the app's own browser or otherwise:
 * a wallet only puts itself into its own app's browser, and Safari extensions do
 * not load in an in-app view. So rather than a dead end, the page hands itself
 * over. These links open this same page, address and all, inside the wallet,
 * where the signature is possible.
 */
function HandOff({ phone }: { phone: boolean }) {
  const [copied, setCopied] = useState(false);
  const here = typeof window === "undefined" ? "" : window.location.href;

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(here);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  };

  if (!phone) {
    return (
      <div className="dep-empty">
        <p>No wallet in this browser.</p>
        <p className="dep-fine">Install MetaMask or Rabby and reload this page.</p>
      </div>
    );
  }

  const bare = here.replace(/^https?:\/\//, "");
  return (
    <div className="dep-connect">
      <p className="dep-empty-title">Open this in your wallet</p>
      <a className="dep-go" href={`https://metamask.app.link/dapp/${bare}`}>
        Open in MetaMask
      </a>
      <a className="dep-go dep-go--quiet" href={`https://go.cb-w.com/dapp?cb_url=${encodeURIComponent(here)}`}>
        Open in Coinbase Wallet
      </a>
      <button type="button" className="dep-go dep-go--quiet" onClick={copy}>
        {copied ? "Link copied" : "Copy the link instead"}
      </button>
      <p className="dep-fine">
        A wallet can only sign inside its own app. These open this same page there, still paying into your Recourse account.
      </p>
    </div>
  );
}

function short(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

/** Wallet errors arrive as paragraphs; the person only needs the reason. */
function describe(cause: unknown): string {
  const text = cause instanceof Error ? cause.message : String(cause);
  if (/user rejected|denied|cancell?ed/i.test(text)) return "You cancelled that in your wallet.";
  if (/insufficient funds/i.test(text)) return "Not enough gas in that wallet to send the transaction.";
  if (/chain|network/i.test(text) && /switch|unsupported|add/i.test(text)) return "Add that network to your wallet, then try again.";
  return text.split("\n")[0].slice(0, 160);
}
