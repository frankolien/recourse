// Prints 160 bytes of calldata for the RIP-7212 precompile carrying a signature that is
// genuinely valid. Needed because an invalid signature and an absent precompile both
// answer empty, so only a real one distinguishes a chain that can verify Face ID from
// one that cannot.
import { generateKeyPairSync, createSign, createHash } from "node:crypto";
const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const msg = Buffer.from("recourse p256 precompile probe");
const hash = createHash("sha256").update(msg).digest();
const sig = createSign("SHA256").update(msg).end().sign({ key: privateKey, dsaEncoding: "ieee-p1363" });
let r = sig.subarray(0, 32), s = sig.subarray(32, 64);
// RIP-7212 rejects the upper half of the curve order, so fold s if the signer landed there.
const N = BigInt("0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
let sv = BigInt("0x" + s.toString("hex"));
if (sv > N / 2n) { sv = N - sv; s = Buffer.from(sv.toString(16).padStart(64, "0"), "hex"); }
const point = publicKey.export({ type: "spki", format: "der" }).subarray(-64);
console.log("0x" + Buffer.concat([hash, r, s, point]).toString("hex"));
