-- Phones that asked to hear about their treasuries. One row per APNs token; a token
-- that Apple reports dead is removed the moment it fails.
CREATE TABLE IF NOT EXISTS push_devices (
    token TEXT PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    -- sandbox for builds from Xcode, production for TestFlight and the App Store.
    environment TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS push_devices_account_idx ON push_devices (account_id);
