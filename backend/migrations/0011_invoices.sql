-- Money someone asked for, and the signature that answers it.
--
-- An invoice is a request for a cheque. The issuer names the payer, the amount and the
-- date it stops being payable, and picks the nonce; the payer answers by signing an
-- EIP-3009 authorization over exactly those terms. That is the whole mechanism, and it
-- is deliberately the same one cheques already use, so nothing new has to be trusted.
--
-- The issuer choosing the nonce is what separates this from asking for money in a chat
-- message. The terms are fixed by the person owed before the payer ever sees them, and
-- the payer can only sign them or not: they cannot quietly change the amount, the
-- recipient, or the expiry, because every one of those fields is inside the signature.
--
-- **No status column**, for the same reason cheques have none. Whether the money moved
-- is answered by the token's authorizationState against (payer_address, nonce). A copy
-- here would drift the moment an invoice was collected, and a wrong "paid" is a worse
-- answer than no answer.

CREATE TABLE IF NOT EXISTS invoices (
    invoice_id BIGSERIAL PRIMARY KEY,
    -- Nulled rather than cascaded: a signed authorization stays collectable on chain
    -- whatever happens to the account row, so deleting it would hide live money.
    issuer_account_id BIGINT REFERENCES accounts(account_id) ON DELETE SET NULL,
    -- Where the money goes. Recorded rather than derived from the account, because the
    -- account may later point its handle at a different wallet and this invoice was
    -- signed for the address that was current when it was issued.
    issuer_address TEXT NOT NULL,
    payer_address TEXT NOT NULL,
    amount_base_units BIGINT NOT NULL,
    -- Unix seconds, mirroring the EIP-3009 window the payer signs over.
    valid_after BIGINT NOT NULL DEFAULT 0,
    valid_before BIGINT NOT NULL,
    nonce TEXT NOT NULL,
    -- What the invoice is for. Not optional: an unexplained demand for money is the
    -- thing people are right to ignore.
    memo TEXT NOT NULL,
    -- Null until the payer signs. Once set, the invoice is answered and the issuer can
    -- submit it whenever they like.
    signature TEXT,
    signed_at TIMESTAMPTZ,
    -- Set when the issuer withdraws the request. Only meaningful while unsigned: once
    -- a signature exists the authorization is live on chain and cancelling the row
    -- would be a lie, so the issuer voids the nonce instead.
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The payer's replay guard, mirrored. Two invoices sharing a payer and a nonce could
-- never both be collected on chain, so storing both would promise something impossible.
CREATE UNIQUE INDEX IF NOT EXISTS invoices_replay_key ON invoices (payer_address, nonce);

-- The inbox query: everything asked of me.
CREATE INDEX IF NOT EXISTS invoices_payer_idx ON invoices (payer_address);

-- The outbox query: everything I asked for, newest first.
CREATE INDEX IF NOT EXISTS invoices_issuer_idx ON invoices (issuer_account_id, created_at DESC);
