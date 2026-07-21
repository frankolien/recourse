-- One-time challenges for wallet-signature auth on write routes. The backend issues a
-- random nonce, the caller signs it inside an EIP-712 message, and the nonce is consumed
-- atomically at verify time so a captured signature cannot be replayed. Rows are short
-- lived; expired ones are pruned on issue.
CREATE TABLE IF NOT EXISTS auth_challenges (
    nonce      TEXT PRIMARY KEY,       -- 0x-prefixed 32-byte hex
    expires_at BIGINT NOT NULL,        -- unix seconds
    consumed   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Buyer-scoped payment lists for the mobile app (GET /api/payments?buyer=0x..).
CREATE INDEX IF NOT EXISTS idx_payments_buyer ON payments (buyer);
