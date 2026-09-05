-- A wallet whose keys are all gone can be given up by its owner, proven by the emailed
-- code, so the same sign-in can start a new one. The row is kept here rather than
-- deleted: the Safe still exists on chain and may still hold money.
CREATE TABLE IF NOT EXISTS smart_accounts_abandoned (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    safe_address TEXT NOT NULL,
    salt_nonce TEXT NOT NULL,
    cloud_owner TEXT NOT NULL,
    device_owner TEXT NOT NULL,
    device_x TEXT NOT NULL,
    device_y TEXT NOT NULL,
    recovery_owner TEXT NOT NULL,
    threshold INT NOT NULL,
    status TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    abandoned_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS smart_accounts_abandoned_account_idx ON smart_accounts_abandoned (account_id, abandoned_at DESC);
