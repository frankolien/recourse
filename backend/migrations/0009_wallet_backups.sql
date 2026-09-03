-- The encrypted wallet key, so an account can carry its wallet to another device.
--
-- What is stored here is ciphertext and nothing else. The device derives a key from a
-- PIN with scrypt and seals the private key under it with AES-GCM; the server sees the
-- envelope, never the PIN and never the key. That is what keeps this from being
-- custody: holding these rows does not let the backend move anyone's funds, and a full
-- dump of this table still leaves an attacker paying scrypt for every guess.
--
-- One backup per account, because the account is what a person signs in as and what
-- they expect their wallet to follow. Re-sealing after a PIN change replaces the row
-- rather than adding to it: an old envelope left behind would still open under the old
-- PIN, which is exactly what changing it was meant to stop.

CREATE TABLE IF NOT EXISTS wallet_backups (
    account_id BIGINT PRIMARY KEY REFERENCES accounts(account_id) ON DELETE CASCADE,
    -- The sealed envelope as the device wrote it. JSONB rather than text so a malformed
    -- blob is rejected on the way in instead of at restore time, when it is too late.
    envelope JSONB NOT NULL,
    -- Kept alongside so a restore can name the wallet before asking for a PIN. It is
    -- also inside the envelope; this copy is for reading without parsing.
    address TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
