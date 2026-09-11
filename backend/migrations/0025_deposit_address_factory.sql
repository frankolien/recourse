-- A cached deposit address is only valid for the factory that issued it.
--
-- The address is a pure function of the account's Safe *and the factory*, because the
-- factory holds the per-chain token and messenger table and is therefore part of the
-- creation code. The first factory was Base only; widening the chain list to eight
-- changed its code and so its address, and every address it had already issued became
-- an address the current factory cannot sweep. The cache had no way to know that, so
-- it kept serving the old answers and the sweeper watched addresses it could never
-- collect from.
--
-- Recording the factory makes a swap miss the cache instead of poisoning it. The rows
-- are deleted rather than backfilled because the table is a cache: losing it costs one
-- call per account and chain, and guessing which factory issued a row would be a
-- guess about where somebody's money can go.
ALTER TABLE deposit_addresses ADD COLUMN IF NOT EXISTS factory TEXT NOT NULL DEFAULT '';

DELETE FROM deposit_addresses;
