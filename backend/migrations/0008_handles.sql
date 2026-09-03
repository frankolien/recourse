-- A handle is how one person names another when sending money: "@frank" rather than a
-- 0x string. It is the first thing that makes this feel like an app instead of a wallet.
--
-- The address lives here rather than on accounts because the account is the durable
-- identity and the address is not: a device change today, and account-scoped key
-- recovery later, both move the address while the handle must keep pointing at the
-- same person. Senders resolve at send time for exactly that reason, so a saved
-- contact never goes stale.
--
-- handle_lower is stored rather than expressed as a UNIQUE index on lower(handle)
-- because the handle is case-preserving for display and case-insensitive for both
-- lookup and uniqueness, and a stored column keeps the constraint and the query
-- reading the same value.

CREATE TABLE IF NOT EXISTS account_handles (
    account_id BIGINT PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
    handle TEXT NOT NULL,
    handle_lower TEXT NOT NULL UNIQUE,
    wallet_address TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Resolution is the hot path: every send that names a person does one lookup by
-- handle_lower before anything is signed.
CREATE INDEX IF NOT EXISTS account_handles_lower_idx ON account_handles (handle_lower);
