-- Passkeys (WebAuthn) as another login method on the provider-agnostic accounts table
-- (provider='passkey', provider_subject=lower(email)). A passkey account can hold one or
-- more credentials. Arc wallet signatures still authorize payment writes; this only
-- affects familiar onboarding.

CREATE TABLE IF NOT EXISTS passkey_credentials (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    -- Raw WebAuthn credential id (unique across all accounts so an authenticator cannot be
    -- registered twice).
    credential_id BYTEA NOT NULL UNIQUE,
    -- The serialized webauthn-rs Passkey (public key, counter, transports). The signature
    -- counter is bumped here on each successful authentication.
    passkey JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_passkey_credentials_account ON passkey_credentials (account_id);

-- Short-lived, single-use server state for an in-flight ceremony, keyed by an opaque
-- challenge id handed to the client. A register row carries the pending identity (the
-- account is created only on finish); an authenticate row carries the account being logged
-- in. Consumed by DELETE ... RETURNING so a challenge is good for exactly one finish.
CREATE TABLE IF NOT EXISTS webauthn_ceremonies (
    challenge_id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    email TEXT,
    given_name TEXT,
    family_name TEXT,
    account_id BIGINT,
    state JSONB NOT NULL,
    expires_at BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
