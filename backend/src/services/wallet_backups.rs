use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;
use crate::services::handles;

/// Generous for an envelope holding a 32 byte key, small enough that this cannot be
/// used as free storage for something else.
const MAX_ENVELOPE_BYTES: usize = 8 * 1024;

/// Fields the device is expected to have written. The server cannot check that the
/// ciphertext is meaningful, but it can refuse a blob that would certainly fail to open
/// later, which is the difference between finding out now and finding out on the new
/// phone with no other copy of the key.
const REQUIRED_FIELDS: &[&str] = &[
    "version",
    "kdf",
    "n",
    "r",
    "p",
    "salt",
    "nonce",
    "ciphertext",
    "address",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredBackup {
    pub envelope: Value,
    pub address: String,
    pub updated_at: String,
}

/// Structural validation only. Deliberately not a decryption attempt, and not a check
/// that the parameters are strong: the server has no PIN and must not be able to reason
/// about the contents, so its whole job is refusing what is obviously unopenable.
fn validate(envelope: &Value) -> Result<String, AccountAuthError> {
    let object = envelope
        .as_object()
        .ok_or_else(|| AccountAuthError::BadRequest("backup envelope must be an object".into()))?;

    for field in REQUIRED_FIELDS {
        if !object.contains_key(*field) {
            return Err(AccountAuthError::BadRequest(format!(
                "backup envelope is missing {field}"
            )));
        }
    }

    let raw = serde_json::to_vec(envelope)
        .map_err(|error| AccountAuthError::Internal(format!("re-encoding envelope: {error}")))?;
    if raw.len() > MAX_ENVELOPE_BYTES {
        return Err(AccountAuthError::BadRequest(
            "backup envelope is too large".into(),
        ));
    }

    let address = object
        .get("address")
        .and_then(Value::as_str)
        .ok_or_else(|| {
            AccountAuthError::BadRequest("backup envelope address must be a string".into())
        })?;

    // Same rule the handle directory applies, so the two can never disagree about what
    // an address is.
    handles::normalize_address(address)
}

/// Store or replace an account's backup.
pub async fn put(
    pool: &PgPool,
    account_id: i64,
    envelope: Value,
) -> Result<StoredBackup, AccountAuthError> {
    let address = validate(&envelope)?;

    let row: (Value, String, chrono::DateTime<chrono::Utc>) = sqlx::query_as(
        "INSERT INTO wallet_backups (account_id, envelope, address) VALUES ($1, $2, $3) \
         ON CONFLICT (account_id) DO UPDATE \
         SET envelope = EXCLUDED.envelope, address = EXCLUDED.address, updated_at = now() \
         RETURNING envelope, address, updated_at",
    )
    .bind(account_id)
    .bind(&envelope)
    .bind(&address)
    .fetch_one(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("storing wallet backup: {error}")))?;

    Ok(StoredBackup {
        envelope: row.0,
        address: row.1,
        updated_at: row.2.to_rfc3339(),
    })
}

pub async fn get(pool: &PgPool, account_id: i64) -> Result<Option<StoredBackup>, AccountAuthError> {
    let row: Option<(Value, String, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT envelope, address, updated_at FROM wallet_backups WHERE account_id = $1",
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading wallet backup: {error}")))?;

    Ok(row.map(|(envelope, address, updated_at)| StoredBackup {
        envelope,
        address,
        updated_at: updated_at.to_rfc3339(),
    }))
}

/// Remove a backup. The device keeps its key either way, so this turns recovery off
/// rather than destroying the wallet.
pub async fn delete(pool: &PgPool, account_id: i64) -> Result<(), AccountAuthError> {
    sqlx::query("DELETE FROM wallet_backups WHERE account_id = $1")
        .bind(account_id)
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("deleting wallet backup: {error}")))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn envelope() -> Value {
        json!({
            "version": 1,
            "kdf": "scrypt",
            "n": 32768, "r": 8, "p": 1,
            "salt": "c2FsdA==",
            "nonce": "bm9uY2U=",
            "ciphertext": "Y2lwaGVy",
            "address": "0xD6c574461d96Ee708f58Fe553049aD4f48BB983A"
        })
    }

    #[test]
    fn accepts_a_well_formed_envelope_and_normalizes_its_address() {
        assert_eq!(
            validate(&envelope()).unwrap(),
            "0xd6c574461d96ee708f58fe553049ad4f48bb983a"
        );
    }

    #[test]
    fn refuses_an_envelope_that_could_never_be_opened() {
        for missing in REQUIRED_FIELDS {
            let mut value = envelope();
            value.as_object_mut().unwrap().remove(*missing);
            assert!(
                validate(&value).is_err(),
                "an envelope with no {missing} must be refused on the way in"
            );
        }
    }

    #[test]
    fn refuses_anything_that_is_not_an_object() {
        assert!(validate(&json!("just a string")).is_err());
        assert!(validate(&json!([1, 2, 3])).is_err());
    }

    #[test]
    fn refuses_a_blob_being_used_as_storage() {
        let mut value = envelope();
        value
            .as_object_mut()
            .unwrap()
            .insert("padding".into(), json!("x".repeat(MAX_ENVELOPE_BYTES + 1)));
        assert!(validate(&value).is_err());
    }

    #[test]
    fn refuses_an_address_the_handle_directory_would_also_refuse() {
        let mut value = envelope();
        value
            .as_object_mut()
            .unwrap()
            .insert("address".into(), json!("not-an-address"));
        assert!(validate(&value).is_err());
    }

    #[test]
    fn never_inspects_the_ciphertext() {
        // The server has no PIN, so a blob whose ciphertext is nonsense is still a
        // valid thing to store: only the device can tell, and only at restore.
        let mut value = envelope();
        value
            .as_object_mut()
            .unwrap()
            .insert("ciphertext".into(), json!("!!!not base64!!!"));
        assert!(validate(&value).is_ok());
    }
}
