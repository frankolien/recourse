use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;
use crate::services::handles;

/// Long enough to say what a cheque is for, short enough not to be a message channel.
const MAX_MEMO_CHARS: usize = 140;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NewCheque {
    pub from: String,
    pub to: String,
    /// Decimal string. USDC base units exceed what JSON numbers carry safely once
    /// amounts get large, and a cheque quietly rounded is a wrong promise.
    pub amount: String,
    pub valid_after: String,
    pub valid_before: String,
    pub nonce: String,
    pub signature: String,
    pub memo: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredCheque {
    pub cheque_id: i64,
    pub from: String,
    pub to: String,
    pub amount: String,
    pub valid_after: String,
    pub valid_before: String,
    pub nonce: String,
    pub signature: String,
    pub memo: Option<String>,
    pub created_at: String,
}

type Row = (
    i64,
    String,
    String,
    i64,
    i64,
    i64,
    String,
    String,
    Option<String>,
    chrono::DateTime<chrono::Utc>,
);

fn present(row: Row) -> StoredCheque {
    StoredCheque {
        cheque_id: row.0,
        from: row.1,
        to: row.2,
        amount: row.3.to_string(),
        valid_after: row.4.to_string(),
        valid_before: row.5.to_string(),
        nonce: row.6,
        signature: row.7,
        memo: row.8,
        created_at: row.9.to_rfc3339(),
    }
}

/// 32 bytes of hex for a nonce, 65 for a signature.
///
/// Shared with invoices, which validate the same authorization fields because an
/// invoice is answered by exactly the signature a cheque is made of.
pub fn fixed_width_hex(
    value: &str,
    bytes: usize,
    field: &str,
) -> Result<String, AccountAuthError> {
    let body = value
        .strip_prefix("0x")
        .or_else(|| value.strip_prefix("0X"))
        .ok_or_else(|| AccountAuthError::BadRequest(format!("{field} must be 0x prefixed hex")))?;
    if body.len() != bytes * 2 || !body.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(AccountAuthError::BadRequest(format!(
            "{field} must be {bytes} bytes of hex"
        )));
    }
    Ok(format!("0x{}", body.to_ascii_lowercase()))
}

pub fn whole_number(value: &str, field: &str) -> Result<i64, AccountAuthError> {
    value
        .parse::<i64>()
        .map_err(|_| AccountAuthError::BadRequest(format!("{field} must be a whole number")))
        .and_then(|parsed| {
            if parsed < 0 {
                Err(AccountAuthError::BadRequest(format!(
                    "{field} cannot be negative"
                )))
            } else {
                Ok(parsed)
            }
        })
}

/// Store a signed cheque so its recipient can find it.
///
/// The server cannot verify the signature is the writer's without recovering it, and
/// deliberately does not try: a cheque with a bad signature simply fails to cash, and
/// the person who loses is the one who wrote it. What is checked is that every field is
/// well formed, so a cheque that could never be cashed is refused at the point someone
/// still believes they have written one.
pub async fn create(
    pool: &PgPool,
    writer_account_id: i64,
    cheque: NewCheque,
) -> Result<StoredCheque, AccountAuthError> {
    let from = handles::normalize_address(&cheque.from)?;
    let to = handles::normalize_address(&cheque.to)?;
    if from == to {
        return Err(AccountAuthError::BadRequest(
            "a cheque cannot be written to yourself".into(),
        ));
    }

    let amount = whole_number(&cheque.amount, "amount")?;
    if amount == 0 {
        return Err(AccountAuthError::BadRequest(
            "a cheque needs an amount above zero".into(),
        ));
    }
    let valid_after = whole_number(&cheque.valid_after, "validAfter")?;
    let valid_before = whole_number(&cheque.valid_before, "validBefore")?;
    if valid_before <= valid_after {
        return Err(AccountAuthError::BadRequest(
            "a cheque must expire after it becomes valid".into(),
        ));
    }

    let nonce = fixed_width_hex(&cheque.nonce, 32, "nonce")?;
    let signature = fixed_width_hex(&cheque.signature, 65, "signature")?;

    let memo = match cheque.memo {
        Some(memo) if memo.chars().count() > MAX_MEMO_CHARS => {
            return Err(AccountAuthError::BadRequest(format!(
                "a memo can be at most {MAX_MEMO_CHARS} characters"
            )))
        }
        Some(memo) if memo.trim().is_empty() => None,
        other => other,
    };

    let row: Row = sqlx::query_as(
        "INSERT INTO cheques (writer_account_id, from_address, to_address, amount_base_units, \
                              valid_after, valid_before, nonce, signature, memo) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) \
         RETURNING cheque_id, from_address, to_address, amount_base_units, valid_after, \
                   valid_before, nonce, signature, memo, created_at",
    )
    .bind(writer_account_id)
    .bind(&from)
    .bind(&to)
    .bind(amount)
    .bind(valid_after)
    .bind(valid_before)
    .bind(&nonce)
    .bind(&signature)
    .bind(&memo)
    .fetch_one(pool)
    .await
    .map_err(|error| match error {
        sqlx::Error::Database(ref db) if db.is_unique_violation() => AccountAuthError::Conflict(
            "a cheque with that nonce already exists for this wallet".into(),
        ),
        other => AccountAuthError::Internal(format!("storing cheque: {other}")),
    })?;

    Ok(present(row))
}

/// Cheques this account wrote.
pub async fn written_by(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<StoredCheque>, AccountAuthError> {
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT cheque_id, from_address, to_address, amount_base_units, valid_after, \
                valid_before, nonce, signature, memo, created_at \
         FROM cheques WHERE writer_account_id = $1 ORDER BY created_at DESC LIMIT 200",
    )
    .bind(account_id)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("listing written cheques: {error}")))?;

    Ok(rows.into_iter().map(present).collect())
}

/// Every address this account has put on file for itself.
///
/// The handle directory and the wallet backup are both written by the account about
/// its own wallet, which is what makes them usable as "who am I" without inventing a
/// second proof of address ownership. An account that has done neither has no inbox,
/// and that is consistent rather than a gap: a handle is how anyone learned where to
/// write you a cheque in the first place.
pub async fn addresses_for(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<String>, AccountAuthError> {
    let rows: Vec<(String,)> = sqlx::query_as(
        "SELECT wallet_address FROM account_handles WHERE account_id = $1 \
         UNION \
         SELECT address FROM wallet_backups WHERE account_id = $1",
    )
    .bind(account_id)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading account addresses: {error}")))?;

    Ok(rows.into_iter().map(|(address,)| address).collect())
}

/// Cheques written to this account.
pub async fn written_to(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<StoredCheque>, AccountAuthError> {
    let addresses = addresses_for(pool, account_id).await?;
    if addresses.is_empty() {
        return Ok(Vec::new());
    }

    let rows: Vec<Row> = sqlx::query_as(
        "SELECT cheque_id, from_address, to_address, amount_base_units, valid_after, \
                valid_before, nonce, signature, memo, created_at \
         FROM cheques WHERE to_address = ANY($1) ORDER BY created_at DESC LIMIT 200",
    )
    .bind(&addresses)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("listing received cheques: {error}")))?;

    Ok(rows.into_iter().map(present).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_and_lowercases_fixed_width_hex() {
        assert_eq!(
            fixed_width_hex(&format!("0x{}", "AB".repeat(32)), 32, "nonce").unwrap(),
            format!("0x{}", "ab".repeat(32))
        );
    }

    #[test]
    fn refuses_hex_of_the_wrong_width() {
        // A short nonce or signature is a cheque that cannot be cashed, and the writer
        // should learn that now rather than when the recipient tries.
        assert!(fixed_width_hex("0xdead", 32, "nonce").is_err());
        assert!(fixed_width_hex(&format!("0x{}", "ab".repeat(64)), 65, "signature").is_err());
        assert!(
            fixed_width_hex(&"ab".repeat(32), 32, "nonce").is_err(),
            "0x prefix is required"
        );
        assert!(fixed_width_hex(&format!("0x{}", "zz".repeat(32)), 32, "nonce").is_err());
    }

    #[test]
    fn refuses_numbers_that_are_not_whole_or_are_negative() {
        assert_eq!(whole_number("1500000", "amount").unwrap(), 1_500_000);
        assert!(whole_number("1.5", "amount").is_err());
        assert!(whole_number("-1", "amount").is_err());
        assert!(whole_number("", "amount").is_err());
    }

    #[test]
    fn accepts_zero_for_valid_after_because_that_means_immediately() {
        assert_eq!(whole_number("0", "validAfter").unwrap(), 0);
    }
}
