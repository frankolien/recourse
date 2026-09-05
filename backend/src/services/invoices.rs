use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;
use crate::services::cheques;
use crate::services::handles;

/// Enough to say what the work was, short enough not to be a contract.
const MAX_MEMO_CHARS: usize = 200;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NewInvoice {
    pub issuer: String,
    pub payer: String,
    /// Decimal string of base units, for the same reason cheques use one: JSON numbers
    /// stop being exact before USDC amounts stop being plausible.
    pub amount: String,
    pub valid_before: String,
    pub nonce: String,
    pub memo: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredInvoice {
    pub invoice_id: i64,
    pub issuer: String,
    pub payer: String,
    pub amount: String,
    pub valid_after: String,
    pub valid_before: String,
    pub nonce: String,
    pub memo: String,
    /// Present once the payer has signed. The client submits this to the token to
    /// collect; until then there is nothing to submit.
    pub signature: Option<String>,
    pub signed_at: Option<String>,
    pub cancelled_at: Option<String>,
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
    Option<chrono::DateTime<chrono::Utc>>,
    Option<chrono::DateTime<chrono::Utc>>,
    chrono::DateTime<chrono::Utc>,
);

const COLUMNS: &str = "invoice_id, issuer_address, payer_address, amount_base_units, \
                       valid_after, valid_before, nonce, memo, signature, signed_at, \
                       cancelled_at, created_at";

fn present(row: Row) -> StoredInvoice {
    StoredInvoice {
        invoice_id: row.0,
        issuer: row.1,
        payer: row.2,
        amount: row.3.to_string(),
        valid_after: row.4.to_string(),
        valid_before: row.5.to_string(),
        nonce: row.6,
        memo: row.7,
        signature: row.8,
        signed_at: row.9.map(|at| at.to_rfc3339()),
        cancelled_at: row.10.map(|at| at.to_rfc3339()),
        created_at: row.11.to_rfc3339(),
    }
}

fn memo(raw: &str) -> Result<String, AccountAuthError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        // An unexplained demand for money is the thing people are right to ignore, so
        // the field is required rather than encouraged.
        return Err(AccountAuthError::BadRequest(
            "say what the invoice is for".into(),
        ));
    }
    if trimmed.chars().count() > MAX_MEMO_CHARS {
        return Err(AccountAuthError::BadRequest(format!(
            "keep it under {MAX_MEMO_CHARS} characters"
        )));
    }
    Ok(trimmed.to_string())
}

/// Issue an invoice: a request for a signature over terms the issuer has fixed.
///
/// Nothing here is authoritative. The row is how the request reaches the payer, and the
/// only thing that will ever move money is the signature the payer chooses to add.
pub async fn create(
    pool: &PgPool,
    issuer_account_id: i64,
    invoice: NewInvoice,
) -> Result<StoredInvoice, AccountAuthError> {
    let issuer = handles::normalize_address(&invoice.issuer)?;
    let payer = handles::normalize_address(&invoice.payer)?;
    if issuer == payer {
        return Err(AccountAuthError::BadRequest(
            "an invoice cannot be sent to yourself".into(),
        ));
    }

    let amount = cheques::whole_number(&invoice.amount, "amount")?;
    if amount == 0 {
        return Err(AccountAuthError::BadRequest(
            "an invoice needs an amount above zero".into(),
        ));
    }
    let valid_before = cheques::whole_number(&invoice.valid_before, "validBefore")?;
    if valid_before == 0 {
        return Err(AccountAuthError::BadRequest(
            "an invoice needs a date it stops being payable".into(),
        ));
    }

    let nonce = cheques::fixed_width_hex(&invoice.nonce, 32, "nonce")?;
    let memo = memo(&invoice.memo)?;

    let row: Row = sqlx::query_as(&format!(
        "INSERT INTO invoices (issuer_account_id, issuer_address, payer_address, \
                               amount_base_units, valid_before, nonce, memo) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING {COLUMNS}"
    ))
    .bind(issuer_account_id)
    .bind(&issuer)
    .bind(&payer)
    .bind(amount)
    .bind(valid_before)
    .bind(&nonce)
    .bind(&memo)
    .fetch_one(pool)
    .await
    .map_err(|error| match error {
        sqlx::Error::Database(ref db) if db.is_unique_violation() => {
            AccountAuthError::Conflict("that invoice already exists".into())
        }
        other => AccountAuthError::Internal(format!("issuing invoice: {other}")),
    })?;

    Ok(present(row))
}

/// Attach the payer's signature.
///
/// Only the addressed payer can answer, and only once. The second condition matters
/// more than it looks: overwriting a signature would let anyone who can reach this
/// endpoint swap a valid authorization for a worthless one and strand the issuer's
/// money behind a request that already looked answered.
pub async fn sign(
    pool: &PgPool,
    payer_account_id: i64,
    invoice_id: i64,
    signature: &str,
) -> Result<StoredInvoice, AccountAuthError> {
    let signature = cheques::signature_hex(signature)?;
    let addresses = cheques::addresses_for(pool, payer_account_id).await?;
    if addresses.is_empty() {
        return Err(AccountAuthError::BadRequest(
            "this account has no wallet on file".into(),
        ));
    }

    let row: Option<Row> = sqlx::query_as(&format!(
        "UPDATE invoices SET signature = $1, signed_at = now() \
         WHERE invoice_id = $2 AND payer_address = ANY($3) \
           AND signature IS NULL AND cancelled_at IS NULL \
         RETURNING {COLUMNS}"
    ))
    .bind(&signature)
    .bind(invoice_id)
    .bind(&addresses)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("signing invoice: {error}")))?;

    match row {
        Some(row) => Ok(present(row)),
        // Deliberately one message for "not yours", "already signed", "cancelled" and
        // "no such invoice". Distinguishing them would let anyone with an account walk
        // invoice ids and learn who is billing whom.
        None => Err(AccountAuthError::BadRequest(
            "that invoice cannot be paid".into(),
        )),
    }
}

/// Withdraw an unanswered request.
///
/// Refused once a signature exists, because at that point the authorization is live on
/// chain and a cancelled row would be a lie: the issuer can still collect. Killing a
/// signed invoice means voiding its nonce on chain, which only the payer can sign.
pub async fn cancel(
    pool: &PgPool,
    issuer_account_id: i64,
    invoice_id: i64,
) -> Result<StoredInvoice, AccountAuthError> {
    let row: Option<Row> = sqlx::query_as(&format!(
        "UPDATE invoices SET cancelled_at = now() \
         WHERE invoice_id = $1 AND issuer_account_id = $2 \
           AND signature IS NULL AND cancelled_at IS NULL \
         RETURNING {COLUMNS}"
    ))
    .bind(invoice_id)
    .bind(issuer_account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("cancelling invoice: {error}")))?;

    match row {
        Some(row) => Ok(present(row)),
        None => Err(AccountAuthError::BadRequest(
            "that invoice cannot be cancelled".into(),
        )),
    }
}

/// Invoices this account issued.
pub async fn issued_by(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<StoredInvoice>, AccountAuthError> {
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "SELECT {COLUMNS} FROM invoices WHERE issuer_account_id = $1 \
         ORDER BY created_at DESC LIMIT 200"
    ))
    .bind(account_id)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("listing issued invoices: {error}")))?;

    Ok(rows.into_iter().map(present).collect())
}

/// Invoices addressed to this account.
///
/// Cancelled ones are withheld: a request the issuer withdrew is not something the
/// payer should still be looking at, and there is nothing left to do about it.
pub async fn addressed_to(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<StoredInvoice>, AccountAuthError> {
    let addresses = cheques::addresses_for(pool, account_id).await?;
    if addresses.is_empty() {
        return Ok(Vec::new());
    }

    let rows: Vec<Row> = sqlx::query_as(&format!(
        "SELECT {COLUMNS} FROM invoices WHERE payer_address = ANY($1) \
           AND cancelled_at IS NULL \
         ORDER BY created_at DESC LIMIT 200"
    ))
    .bind(&addresses)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("listing received invoices: {error}")))?;

    Ok(rows.into_iter().map(present).collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_memo_is_required_and_trimmed() {
        assert_eq!(memo("  design work  ").unwrap(), "design work");
        assert!(memo("").is_err());
        assert!(memo("   ").is_err());
    }

    #[test]
    fn a_memo_longer_than_the_cap_is_refused() {
        assert!(memo(&"a".repeat(MAX_MEMO_CHARS)).is_ok());
        assert!(memo(&"a".repeat(MAX_MEMO_CHARS + 1)).is_err());
    }

    #[test]
    fn a_memo_is_counted_in_characters_not_bytes() {
        // Emoji and accents are one character each to a person writing the memo, and
        // counting bytes would refuse a note that looks well under the limit.
        assert!(memo(&"é".repeat(MAX_MEMO_CHARS)).is_ok());
    }
}
