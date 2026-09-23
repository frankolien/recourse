#!/usr/bin/env node
// Reads and updates the text a TestFlight tester sees, through the App Store Connect API.
//
//   ops/appstore-text.mjs show
//   ops/appstore-text.mjs set-description path/to/text.md
//   ops/appstore-text.mjs set-whats-new  path/to/text.md
//
// The description is the app's, and appears on the public join page before anyone has
// installed anything. What to Test belongs to one build and appears in the TestFlight
// app beside the Install button.
//
// Credentials come from the environment and are never printed:
//   ASC_KEY_ID, ASC_KEY_PATH (the .p8, kept in backend/secrets/), and ASC_ISSUER_ID
//   for a team key. An individual key has no issuer id, so leaving it unset selects
//   the individual shape rather than failing.
//
// Signing is ES256 with node's own crypto, so this has no dependencies. Apple wants the
// raw r|s pair rather than the ASN.1 wrapper openssl produces by default, which is what
// dsaEncoding: "ieee-p1363" asks for.
import { createSign, sign as cryptoSign } from "node:crypto";
import { readFileSync } from "node:fs";

const API = "https://api.appstoreconnect.apple.com/v1";
const BUNDLE_ID = process.env.ASC_BUNDLE_ID ?? "com.recourse.buyer";

const need = (name) => {
  const value = process.env[name];
  if (!value) {
    console.error(`missing ${name}. See the comment at the top of this file.`);
    process.exit(1);
  }
  return value;
};

const b64url = (input) =>
  Buffer.from(input).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function token() {
  const keyId = need("ASC_KEY_ID");
  const issuer = process.env.ASC_ISSUER_ID?.trim();
  const key = readFileSync(need("ASC_KEY_PATH"), "utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  // The two kinds of key are told apart by their payload and nothing else. A team key
  // names its issuer; an individual key has no issuer and names the subject "user"
  // instead. Sending the wrong shape returns a 401 that reads like a bad key, so the
  // presence of an issuer id decides it rather than a flag someone has to remember.
  const claims = issuer
    ? { iss: issuer, iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" }
    : { sub: "user", iat: now, exp: now + 15 * 60, aud: "appstoreconnect-v1" };
  console.error(`authenticating with ${issuer ? "a team key" : "an individual key"}`);
  // Apple rejects anything longer than twenty minutes.
  const payload = b64url(JSON.stringify(claims));
  const signature = cryptoSign("sha256", Buffer.from(`${header}.${payload}`), {
    key,
    dsaEncoding: "ieee-p1363",
  });
  return `${header}.${payload}.${b64url(signature)}`;
}

const jwt = token();

async function call(path, options = {}) {
  const response = await fetch(path.startsWith("http") ? path : `${API}${path}`, {
    ...options,
    headers: {
      Authorization: `Bearer ${jwt}`,
      "Content-Type": "application/json",
      ...(options.headers ?? {}),
    },
  });
  const text = await response.text();
  if (!response.ok) {
    // Apple's errors carry the useful part in detail, and the status alone is not it.
    let detail = text;
    try {
      detail = JSON.parse(text).errors?.map((e) => `${e.title}: ${e.detail}`).join("; ") ?? text;
    } catch {}
    throw new Error(`${response.status} on ${path}: ${detail}`);
  }
  return text ? JSON.parse(text) : null;
}

async function app() {
  const found = await call(`/apps?filter[bundleId]=${encodeURIComponent(BUNDLE_ID)}`);
  const row = found.data?.[0];
  if (!row) throw new Error(`no app with bundle id ${BUNDLE_ID} on this account`);
  return row;
}

async function descriptionLocalization(appId) {
  const list = await call(`/apps/${appId}/betaAppLocalizations`);
  const row = list.data?.[0];
  if (!row) throw new Error("this app has no beta localization to edit yet");
  return row;
}

async function latestBuildLocalization(appId) {
  // The relationship under an app refuses sort, so the newest build comes from the
  // top level collection filtered to this app, which accepts it.
  const builds = await call(
    `/builds?filter[app]=${appId}&sort=-uploadedDate&limit=1`,
  );
  const build = builds.data?.[0];
  if (!build) throw new Error("no build uploaded yet, so there is no What to Test to set");
  const list = await call(`/builds/${build.id}/betaBuildLocalizations`);
  const row = list.data?.[0];
  if (!row) throw new Error("that build has no localization to edit yet");
  return { build, row };
}

const [command, file] = process.argv.slice(2);

const row = await app();
console.log(`app: ${row.attributes.name} (${BUNDLE_ID}, id ${row.id})`);

if (command === "show") {
  const localization = await descriptionLocalization(row.id);
  console.log(`\n--- beta app description (${localization.attributes.locale}) ---`);
  console.log(localization.attributes.description ?? "(empty)");
  console.log(`\nfeedback email: ${localization.attributes.feedbackEmail ?? "(none)"}`);
  try {
    const { build, row: buildRow } = await latestBuildLocalization(row.id);
    console.log(`\n--- what to test, build ${build.attributes.version} ---`);
    console.log(buildRow.attributes.whatsNew ?? "(empty)");
  } catch (error) {
    console.log(`\nwhat to test: ${error.message}`);
  }
} else if (command === "set-description") {
  if (!file) throw new Error("give a file holding the new text");
  const description = readFileSync(file, "utf8").trim();
  const localization = await descriptionLocalization(row.id);
  await call(`/betaAppLocalizations/${localization.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: { type: "betaAppLocalizations", id: localization.id, attributes: { description } },
    }),
  });
  console.log(`\nbeta app description updated, ${description.length} characters.`);
} else if (command === "set-whats-new") {
  if (!file) throw new Error("give a file holding the new text");
  const whatsNew = readFileSync(file, "utf8").trim();
  const { build, row: buildRow } = await latestBuildLocalization(row.id);
  await call(`/betaBuildLocalizations/${buildRow.id}`, {
    method: "PATCH",
    body: JSON.stringify({
      data: { type: "betaBuildLocalizations", id: buildRow.id, attributes: { whatsNew } },
    }),
  });
  console.log(`\nwhat to test updated on build ${build.attributes.version}.`);
} else {
  console.error("\nusage: show | set-description <file> | set-whats-new <file>");
  process.exit(1);
}
