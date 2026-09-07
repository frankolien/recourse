-- Deposit addresses on chains that are not Arc.
--
-- The address is a pure function of the account's Safe, so this table is a cache of
-- what the factory answers rather than a source of truth: losing it costs one call per
-- account, not anybody's money. It exists so the sweeper has a list to watch without
-- asking the chain about every account on every cycle.
CREATE TABLE IF NOT EXISTS deposit_addresses (
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    chain_id BIGINT NOT NULL,
    address TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, chain_id)
);

CREATE INDEX IF NOT EXISTS deposit_addresses_by_chain ON deposit_addresses (chain_id);

-- Where the sweeper has read up to on each chain. The first run starts at the head, so
-- it does not try to sweep deposits from before the feature existed.
CREATE TABLE IF NOT EXISTS deposit_sweep_cursor (
    chain_id BIGINT PRIMARY KEY,
    block BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
