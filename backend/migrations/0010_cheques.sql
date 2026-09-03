-- Signed cheques, waiting to be cashed.
--
-- A cheque is an EIP-3009 authorization the writer signed offline. This table is only
-- how it reaches the person it was written to; it carries no authority of its own. The
-- signature is safe to store because a cheque is not bearer: `to` is signed over, so
-- someone who steals the row can at most pay the gas to deliver the money to its
-- intended recipient.
--
-- **There is deliberately no status column.** Whether a cheque has been cashed or
-- voided is answered by the token's own authorizationState, and a copy here would drift
-- from the chain the moment anyone cashed one without telling us. The chain is the
-- source of truth for what happened; this table only remembers what was promised.

CREATE TABLE IF NOT EXISTS cheques (
    cheque_id BIGSERIAL PRIMARY KEY,
    -- Nulled rather than cascaded if the account goes away: the authorization stays
    -- valid on chain regardless, so deleting the row would hide a cheque that can
    -- still be cashed.
    writer_account_id BIGINT REFERENCES accounts(account_id) ON DELETE SET NULL,
    from_address TEXT NOT NULL,
    to_address TEXT NOT NULL,
    amount_base_units BIGINT NOT NULL,
    valid_after BIGINT NOT NULL,
    valid_before BIGINT NOT NULL,
    nonce TEXT NOT NULL,
    signature TEXT NOT NULL,
    memo TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The token's own replay guard, mirrored. Two cheques sharing a writer and a nonce can
-- never both be cashable on chain, so storing both would promise something impossible.
CREATE UNIQUE INDEX IF NOT EXISTS cheques_replay_key ON cheques (from_address, nonce);

-- The inbox query: everything written to me.
CREATE INDEX IF NOT EXISTS cheques_recipient_idx ON cheques (to_address);
