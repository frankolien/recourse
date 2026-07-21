-- Indexed projection of onchain state. The chain is the source of truth; this
-- table is a queryable cache the read API serves. u128 amounts are stored as text
-- to avoid a numeric dependency (demo values are small but the type stays exact).

CREATE TABLE IF NOT EXISTS policies (
    policy_id BIGINT PRIMARY KEY,
    merchant TEXT NOT NULL,
    dispute_window BIGINT NOT NULL,
    default_refund_bps INT NOT NULL,
    policy_hash TEXT NOT NULL,
    rules JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payments (
    payment_id BIGINT PRIMARY KEY,
    buyer TEXT NOT NULL,
    merchant TEXT NOT NULL,
    beneficiary TEXT NOT NULL,
    policy_id BIGINT NOT NULL,
    amount TEXT NOT NULL,
    shares TEXT NOT NULL,
    paid_at BIGINT NOT NULL,
    filed_at BIGINT NOT NULL,
    claim_type INT NOT NULL,
    evidence_mask INT NOT NULL,
    att_type INT NOT NULL,
    att_value INT NOT NULL,
    evidence_root TEXT NOT NULL,
    verdict_bps INT NOT NULL,
    status INT NOT NULL,
    -- Verdict fields come from the onchain previewVerdict call, not recomputed here.
    refund_bps INT,
    requires_return BOOLEAN,
    rule_index INT,
    matched BOOLEAN,
    verdict_hash TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_merchant ON payments (merchant);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments (status);
CREATE INDEX IF NOT EXISTS idx_payments_filed_at ON payments (filed_at);

-- The active deployment this projection mirrors. paymentIds restart at 1 on a
-- contract redeploy, so rows from a prior escrow would masquerade as current. On
-- startup we compare the configured escrow/chain to this single row and, if it
-- changed, truncate the projection before reindexing.
CREATE TABLE IF NOT EXISTS index_meta (
    id INT PRIMARY KEY DEFAULT 1,
    escrow TEXT NOT NULL,
    chain_id BIGINT NOT NULL,
    CONSTRAINT index_meta_single_row CHECK (id = 1)
);
