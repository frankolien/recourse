-- Generalize account identity from Apple-only to any social provider (Apple, Google).
-- The identity is now (provider, provider_subject); linked Arc wallet addresses remain the
-- authority for payment writes, so this only affects familiar onboarding, not settlement.
ALTER TABLE accounts RENAME COLUMN apple_subject TO provider_subject;
ALTER TABLE accounts DROP CONSTRAINT IF EXISTS accounts_apple_subject_key;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'apple';
ALTER TABLE accounts ALTER COLUMN provider DROP DEFAULT;
ALTER TABLE accounts ADD CONSTRAINT accounts_provider_identity_key UNIQUE (provider, provider_subject);
