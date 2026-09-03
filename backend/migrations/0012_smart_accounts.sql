-- The account's money moves from one key to a Safe with three owners, any two to
-- spend: the Cloud Key (the EOA the app already had), the Device Key (a P-256 key in
-- the phone's Secure Enclave, standing behind a P256Owner contract) and the Recovery
-- Key (held here, sealed, and only ever used to swap a Device Key). See
-- docs/keys-and-recovery.md.
--
-- One row per account. The Safe address is the account's address from now on: the
-- handle points at it, deposits go to it, cheques are signed by it. The salt is kept
-- so the address can be re-derived and audited; the device key's coordinates are kept
-- so a rotation leaves a record of what was swapped for what.
CREATE TABLE IF NOT EXISTS smart_accounts (
    account_id BIGINT PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
    safe_address TEXT NOT NULL UNIQUE,
    salt_nonce TEXT NOT NULL,
    cloud_owner TEXT NOT NULL,
    device_owner TEXT NOT NULL,
    device_x TEXT NOT NULL,
    device_y TEXT NOT NULL,
    recovery_owner TEXT NOT NULL,
    threshold INT NOT NULL DEFAULT 2,
    -- 'deploying' until both contracts are confirmed with the expected owner set,
    -- then 'live'. A row stuck in 'deploying' is retried by the next provision call.
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The Recovery Key. Sealed with AES-256-GCM under a server-side wrapping key that never
-- reaches the database; key_id names which wrapping key, so moving to a KMS later is a
-- re-seal rather than a rewrite. Holding this row is not custody: it is one of three
-- owners and the code only ever signs owner swaps with it.
CREATE TABLE IF NOT EXISTS recovery_signers (
    account_id BIGINT PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
    address TEXT NOT NULL UNIQUE,
    key_id TEXT NOT NULL,
    sealed BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Emailed codes that release the Recovery Key for one purpose. The code is stored
-- hashed; a verified challenge hands out a grant id that a single rotation spends.
CREATE TABLE IF NOT EXISTS recovery_challenges (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    purpose TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    grant_expires_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    grant_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS recovery_challenges_account_idx
    ON recovery_challenges (account_id, created_at DESC);

-- Every Device Key swap, prepared first (the Safe transaction is fixed and its hash
-- handed to the phone for the Cloud Key to sign) and executed second (the Recovery
-- Key adds its signature and the transaction is submitted).
CREATE TABLE IF NOT EXISTS device_rotations (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    grant_id TEXT NOT NULL,
    old_device_owner TEXT NOT NULL,
    new_device_owner TEXT NOT NULL,
    new_device_x TEXT NOT NULL,
    new_device_y TEXT NOT NULL,
    prev_owner TEXT NOT NULL,
    safe_nonce TEXT NOT NULL,
    safe_tx_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    tx_hash TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    executed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS device_rotations_account_idx ON device_rotations (account_id, created_at DESC);
