-- The escrow state does not expose a payment's orderRef (it lives in the Paid event),
-- but the order manifest system needs paymentId -> orderRef to resolve what was bought.
-- The indexer backfills this column from event logs; NULL means not yet synced.
ALTER TABLE payments ADD COLUMN order_ref TEXT;
