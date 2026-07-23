-- Email/password identities reuse the provider-agnostic accounts table
-- (provider='email', provider_subject=lower(email)). Only these rows carry a password
-- hash; social rows (apple, google) leave it NULL. Stored as an Argon2id PHC string
-- (algorithm, params, salt and digest together), never plaintext.
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS password_hash TEXT;
