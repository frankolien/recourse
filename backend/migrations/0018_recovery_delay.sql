-- A waiting period on the two changes that can take an account away from its owner.
--
-- Swapping the Device Key needs the Cloud Key and the Recovery Key, which is exactly
-- the pair someone holds if they have taken your Apple ID and your inbox. Swapping the
-- Cloud Key needs the Device Key and the Recovery Key, which is the pair someone holds
-- if they have your unlocked phone and your inbox. Neither should complete the moment
-- it is asked for, because the person losing the account is not in the room.
--
-- So both are scheduled rather than executed, the key being replaced is told, and
-- anyone still holding a key can stop it before the clock runs out.

ALTER TABLE device_rotations ADD COLUMN IF NOT EXISTS ready_at TIMESTAMPTZ;
ALTER TABLE device_rotations ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- Rows written before the delay existed executed immediately and are already spent;
-- dating them to their own creation keeps them readable rather than pending forever.
UPDATE device_rotations SET ready_at = created_at WHERE ready_at IS NULL;

-- Replacing the Cloud Key, for someone who lost their iCloud and never set a recovery
-- PIN. Signed by the Device Key on the phone and the Recovery Key here, so the phone
-- is the thing that proves the person is who they say.
CREATE TABLE IF NOT EXISTS cloud_rotations (
    id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    grant_id TEXT NOT NULL,
    old_cloud_owner TEXT NOT NULL,
    new_cloud_owner TEXT NOT NULL,
    prev_owner TEXT NOT NULL,
    safe_nonce TEXT NOT NULL,
    safe_tx_hash TEXT NOT NULL,
    status TEXT NOT NULL,
    tx_hash TEXT,
    ready_at TIMESTAMPTZ NOT NULL,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    executed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS cloud_rotations_account_idx ON cloud_rotations (account_id, status);
CREATE INDEX IF NOT EXISTS device_rotations_pending_idx ON device_rotations (account_id, status);
