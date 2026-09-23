# Backend secrets

Two `.p8` files live here and they are not interchangeable. Both are 257 bytes, both
begin `-----BEGIN PRIVATE KEY-----`, and nothing inside either one says what it is for,
so the only way to tell them apart is the key id in the filename and this table.

| File | Key id | What it is | What breaks without it |
| --- | --- | --- | --- |
| `AuthKey_XY9C96WBZL.p8` | XY9C96WBZL | Sign in with Apple, read by the backend at `APPLE_PRIVATE_KEY_PATH` | Nobody can sign in with an Apple ID. This one is live |
| `AuthKey_TGGCX9YNF5.p8` | TGGCX9YNF5 | App Store Connect API, a team key, used by `ops/appstore-text.mjs` | TestFlight text has to be edited by hand |

Using one where the other belongs returns `401 Authentication credentials are missing
or invalid`, which reads like a corrupt key rather than the wrong key.

Apple lets you download a `.p8` once. Losing one means revoking it and generating
another, so these are not reproducible from anywhere.

`backend/secrets/*` is gitignored. Nothing here may be committed, copied into the iOS
app, or pasted into a chat. Filenames, key ids and issuer ids are identifiers rather
than secrets and are safe to say out loud; the contents never are.
