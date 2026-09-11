"use client";

// Spike, not a feature. The other half of the phone's "Passkey PRF probe": the same
// passkey, asked through mera's own library at the same relying party, must print
// the same accounts the phone prints. If it does, one passkey is one account on
// every surface. If it does not, the derivation on one side is wrong and the pinned
// vectors say which.

import { useState } from "react";
import {
  createEd25519SigningSession,
  createPasskeyWithPrfOutput,
  createSecp256k1SigningSession,
  getEvmAddress,
  getPasskeyPrfOutput,
  getSolanaAddress,
} from "@category-labs/mera";
import { HDKey } from "@scure/bip32";
import { entropyToMnemonic, mnemonicToSeedSync } from "@scure/bip39";
import { wordlist } from "@scure/bip39/wordlists/english";

type Line = { ok: boolean; text: string };

const hex = (bytes: Uint8Array) => Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

// Copies into fresh ArrayBuffers because WebCrypto's types refuse a view that could
// sit on a SharedArrayBuffer.
async function hmacSha512(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const own = (bytes: Uint8Array) => new Uint8Array(bytes).buffer as ArrayBuffer;
  const k = await crypto.subtle.importKey("raw", own(key), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, own(data)));
}

// SLIP-0010 over Ed25519 at m/44'/501'/index'/0', mera's Solana path. Every step
// is hardened, which is the only kind the curve allows.
async function slip10Ed25519(seed: Uint8Array, path: number[]): Promise<Uint8Array> {
  let I = await hmacSha512(new TextEncoder().encode("ed25519 seed"), seed);
  let key = I.slice(0, 32);
  let code = I.slice(32);
  for (const step of path) {
    const index = (step + 0x80000000) >>> 0;
    const data = new Uint8Array(37);
    data.set(key, 1);
    data[33] = index >>> 24;
    data[34] = (index >>> 16) & 0xff;
    data[35] = (index >>> 8) & 0xff;
    data[36] = index & 0xff;
    I = await hmacSha512(code, data);
    key = I.slice(0, 32);
    code = I.slice(32);
  }
  return key;
}

async function accountsFrom(prfOutput: Uint8Array): Promise<Line[]> {
  const mnemonic = entropyToMnemonic(prfOutput, wordlist);
  const seed = mnemonicToSeedSync(mnemonic);
  const evmKey = HDKey.fromMasterSeed(seed).derive("m/44'/60'/0'/0/0").privateKey;
  if (!evmKey) throw new Error("no EVM key at the path");
  const evm = createSecp256k1SigningSession({ privateKey: evmKey });
  const edSeed = await slip10Ed25519(seed, [44, 501, 0, 0]);
  const ed = createEd25519SigningSession({ privateKey: edSeed });
  const lines = [
    { ok: true, text: `EVM ${getEvmAddress(evm.publicKey)}` },
    { ok: true, text: `Ed25519 ${hex(ed.publicKey)}` },
    { ok: true, text: `Solana ${getSolanaAddress(ed.publicKey)}` },
  ];
  evm.end();
  ed.end();
  return lines;
}

export default function PasskeySpikePage() {
  const [log, setLog] = useState<Line[]>([]);
  const [busy, setBusy] = useState(false);

  const say = (ok: boolean, text: string) => setLog((l) => [...l, { ok, text }]);

  const run = async (how: "create" | "existing") => {
    setBusy(true);
    setLog([]);
    const rpId = window.location.hostname;
    try {
      say(true, `relying party ${rpId}`);
      const result =
        how === "create"
          ? await createPasskeyWithPrfOutput({
              rp: { id: rpId, name: "Recourse" },
              user: { name: `spike-${Date.now()}`, displayName: "Passkey spike" },
            })
          : await getPasskeyPrfOutput({ rpId });
      say(true, `PRF output ${result.prfOutput.length} bytes, ${hex(result.prfOutput.slice(0, 8))}...`);
      for (const line of await accountsFrom(result.prfOutput)) say(line.ok, line.text);
      result.prfOutput.fill(0);
    } catch (error) {
      say(false, error instanceof Error ? `${error.name}: ${error.message}` : String(error));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="spk">
      <style>{`
        .spk { min-height: 100dvh; background: #070907; color: #e6f0e6; font: 15px/1.5 -apple-system, system-ui, sans-serif; padding: 28px 20px 60px; max-width: 560px; margin: 0 auto; }
        .spk h1 { font-size: 20px; margin: 0 0 6px; }
        .spk p { color: #9db39d; margin: 0 0 22px; }
        .spk button { display: block; width: 100%; padding: 14px; margin-bottom: 10px; border: 1px solid #234023; border-radius: 12px; background: #0f170f; color: #e6f0e6; font: inherit; font-weight: 600; cursor: pointer; }
        .spk button:disabled { opacity: 0.5; cursor: default; }
        .spk ol { list-style: none; padding: 0; margin: 24px 0 0; }
        .spk li { font: 13px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; padding: 8px 0; border-top: 1px solid #172317; }
        .spk li.bad { color: #f0a0a0; }
      `}</style>
      <h1>Passkey account spike</h1>
      <p>
        Same passkey, same relying party, mera&apos;s derivation. The phone&apos;s probe must print these exact
        accounts.
      </p>
      <button disabled={busy} onClick={() => run("existing")}>
        Use a passkey I already have here
      </button>
      <button disabled={busy} onClick={() => run("create")}>
        Create a new passkey
      </button>
      <ol>
        {log.map((line, i) => (
          <li key={i} className={line.ok ? "" : "bad"}>
            {line.ok ? "✓" : "✗"} {line.text}
          </li>
        ))}
      </ol>
    </main>
  );
}
