-- Off-chain account identity for familiar mobile onboarding. Apple identifies the
-- account; linked Arc wallet addresses remain the authority for payment writes.

CREATE TABLE IF NOT EXISTS apple_auth_challenges (
    nonce_hash BYTEA PRIMARY KEY,
    expires_at BIGINT NOT NULL,
    consumed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS accounts (
    account_id BIGSERIAL PRIMARY KEY,
    apple_subject TEXT NOT NULL UNIQUE,
    email TEXT,
    given_name TEXT,
    family_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS account_sessions (
    session_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    access_token_hash BYTEA NOT NULL UNIQUE,
    refresh_token_hash BYTEA NOT NULL UNIQUE,
    access_expires_at BIGINT NOT NULL,
    refresh_expires_at BIGINT NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_sessions_account ON account_sessions (account_id);
CREATE INDEX IF NOT EXISTS idx_account_sessions_refresh ON account_sessions (refresh_token_hash);
