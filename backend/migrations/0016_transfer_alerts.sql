-- Where the received-money watcher has read up to. One row; the first run starts at
-- the chain head, so nobody is told about deposits from before the feature existed.
CREATE TABLE IF NOT EXISTS transfer_alert_cursor (
    id INT PRIMARY KEY,
    block BIGINT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
