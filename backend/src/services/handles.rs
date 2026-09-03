use serde::Serialize;
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;

/// Long enough to be distinctive, short enough to say out loud.
const MIN_LEN: usize = 3;
const MAX_LEN: usize = 20;

/// Names that must never resolve to a stranger. A handle is what someone reads before
/// sending money, so "@recourse" or "@support" pointing at an arbitrary account is a
/// phishing primitive rather than a naming collision.
const RESERVED: &[&str] = &[
    "recourse", "support", "help", "admin", "root", "system", "team", "official", "circle", "usdc",
    "arc", "wallet", "security", "billing", "payments", "refund", "me", "you", "new", "settings",
    "about", "legal", "privacy", "terms", "api",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Handle {
    pub handle: String,
    pub address: String,
}

/// Case-preserving for display, case-insensitive for lookup and uniqueness.
///
/// The charset is deliberately narrow. Handles are read aloud, typed from memory and
/// compared by eye before money moves, so anything that lets two distinct handles look
/// alike is a security question, not a formatting preference: no unicode, no leading or
/// trailing separator, and no run of separators that a reader would collapse.
pub fn normalize(input: &str) -> Result<(String, String), AccountAuthError> {
    let handle = input.trim().trim_start_matches('@');

    // Charset before length, so a name with non-ASCII characters is told what is
    // actually wrong with it rather than being measured in bytes and called too long.
    if !handle
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.')
    {
        return Err(AccountAuthError::BadRequest(
            "a handle can use letters, numbers, underscore and dot".into(),
        ));
    }
    if handle.len() < MIN_LEN {
        return Err(AccountAuthError::BadRequest(format!(
            "a handle needs at least {MIN_LEN} characters"
        )));
    }
    if handle.len() > MAX_LEN {
        return Err(AccountAuthError::BadRequest(format!(
            "a handle can be at most {MAX_LEN} characters"
        )));
    }
    let first = handle.chars().next().unwrap_or('_');
    let last = handle.chars().last().unwrap_or('_');
    if !first.is_ascii_alphanumeric() || !last.is_ascii_alphanumeric() {
        return Err(AccountAuthError::BadRequest(
            "a handle must start and end with a letter or number".into(),
        ));
    }
    if handle.contains("..")
        || handle.contains("__")
        || handle.contains("._")
        || handle.contains("_.")
    {
        return Err(AccountAuthError::BadRequest(
            "a handle cannot repeat a dot or underscore".into(),
        ));
    }

    let lower = handle.to_ascii_lowercase();
    if RESERVED.contains(&lower.as_str()) {
        return Err(AccountAuthError::Conflict("that handle is reserved".into()));
    }

    Ok((handle.to_string(), lower))
}

/// Rejects anything that is not a 20-byte hex address. The handle is a promise about
/// where money lands, so a malformed address must fail at claim time rather than at
/// send time in someone else's app.
pub fn normalize_address(input: &str) -> Result<String, AccountAuthError> {
    let address = input.trim();
    let body = address
        .strip_prefix("0x")
        .or_else(|| address.strip_prefix("0X"));
    match body {
        Some(body) if body.len() == 40 && body.chars().all(|c| c.is_ascii_hexdigit()) => {
            Ok(format!("0x{}", body.to_ascii_lowercase()))
        }
        _ => Err(AccountAuthError::BadRequest(
            "wallet address must be a 20 byte hex string".into(),
        )),
    }
}

/// Claim a handle, or move an existing one to a new address.
///
/// One handle per account by primary key, and one account per handle by the unique
/// index. Claiming is therefore an upsert on the account, and the race two devices can
/// actually run, both claiming the same free name, is settled by the database rather
/// than by a check-then-write in application code.
pub async fn claim(
    pool: &PgPool,
    account_id: i64,
    requested: &str,
    address: &str,
) -> Result<Handle, AccountAuthError> {
    let (handle, lower) = normalize(requested)?;
    let address = normalize_address(address)?;

    let taken: Option<i64> =
        sqlx::query_scalar("SELECT account_id FROM account_handles WHERE handle_lower = $1")
            .bind(&lower)
            .fetch_optional(pool)
            .await
            .map_err(|error| AccountAuthError::Internal(format!("reading handle: {error}")))?;

    if taken.is_some_and(|owner| owner != account_id) {
        return Err(AccountAuthError::Conflict("that handle is taken".into()));
    }

    sqlx::query(
        "INSERT INTO account_handles (account_id, handle, handle_lower, wallet_address) \
         VALUES ($1, $2, $3, $4) \
         ON CONFLICT (account_id) DO UPDATE \
         SET handle = EXCLUDED.handle, handle_lower = EXCLUDED.handle_lower, \
             wallet_address = EXCLUDED.wallet_address, updated_at = now()",
    )
    .bind(account_id)
    .bind(&handle)
    .bind(&lower)
    .bind(&address)
    .fetch_optional(pool)
    .await
    .map_err(|error| match error {
        // The unique index caught the race the SELECT above could not.
        sqlx::Error::Database(ref db) if db.is_unique_violation() => {
            AccountAuthError::Conflict("that handle is taken".into())
        }
        other => AccountAuthError::Internal(format!("claiming handle: {other}")),
    })?;

    Ok(Handle { handle, address })
}

/// Resolve a handle to the address money should go to. Public: a sender does not have
/// an account with us, and requiring one would make paying a Recourse user harder than
/// paying anyone else.
pub async fn resolve(pool: &PgPool, requested: &str) -> Result<Handle, AccountAuthError> {
    let (_, lower) = normalize(requested)?;

    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT handle, wallet_address FROM account_handles WHERE handle_lower = $1",
    )
    .bind(&lower)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("resolving handle: {error}")))?;

    match row {
        Some((handle, address)) => Ok(Handle { handle, address }),
        None => Err(AccountAuthError::BadRequest("no such handle".into())),
    }
}

/// The signed-in account's own handle, if it has claimed one.
pub async fn for_account(
    pool: &PgPool,
    account_id: i64,
) -> Result<Option<Handle>, AccountAuthError> {
    let row: Option<(String, String)> =
        sqlx::query_as("SELECT handle, wallet_address FROM account_handles WHERE account_id = $1")
            .bind(account_id)
            .fetch_optional(pool)
            .await
            .map_err(|error| AccountAuthError::Internal(format!("reading own handle: {error}")))?;

    Ok(row.map(|(handle, address)| Handle { handle, address }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(input: &str) -> (String, String) {
        normalize(input).expect("expected a valid handle")
    }

    #[test]
    fn accepts_a_plain_handle_with_or_without_the_at_sign() {
        assert_eq!(ok("frank"), ("frank".into(), "frank".into()));
        assert_eq!(ok("@frank"), ("frank".into(), "frank".into()));
        assert_eq!(ok("  @frank  "), ("frank".into(), "frank".into()));
    }

    #[test]
    fn preserves_case_for_display_and_folds_it_for_lookup() {
        // Two people cannot hold FrankOlien and frankolien, but the one who claimed it
        // keeps their capitals.
        assert_eq!(ok("FrankOlien"), ("FrankOlien".into(), "frankolien".into()));
    }

    #[test]
    fn explains_a_unicode_name_by_its_characters_not_its_byte_length() {
        // Cyrillic a is two bytes, so a check ordered the other way would call a short
        // name too long and leave the user with no idea what to change.
        let message = normalize("frаnk").unwrap_err().parts().1;
        assert!(message.contains("letters, numbers"), "got: {message}");
    }

    #[test]
    fn rejects_lengths_outside_the_range() {
        assert!(normalize("ab").is_err());
        assert!(normalize(&"a".repeat(21)).is_err());
        assert!(normalize(&"a".repeat(20)).is_ok());
    }

    #[test]
    fn rejects_anything_that_could_be_read_as_another_handle() {
        // Unicode look-alikes are the whole reason the charset is ASCII only.
        assert!(normalize("frаnk").is_err(), "cyrillic a must not pass");
        assert!(normalize("frank olien").is_err());
        assert!(normalize("frank-olien").is_err());
        assert!(normalize("_frank").is_err());
        assert!(normalize("frank.").is_err());
        assert!(normalize("fr..ank").is_err());
        assert!(normalize("fr__ank").is_err());
    }

    #[test]
    fn refuses_names_that_would_impersonate_the_product_or_the_chain() {
        for name in ["recourse", "Support", "USDC", "arc", "refund"] {
            assert!(normalize(name).is_err(), "{name} must be reserved");
        }
    }

    #[test]
    fn normalizes_addresses_and_rejects_malformed_ones() {
        assert_eq!(
            normalize_address("0xD6c574461d96Ee708f58Fe553049aD4f48BB983A").unwrap(),
            "0xd6c574461d96ee708f58fe553049ad4f48bb983a"
        );
        assert!(normalize_address("d6c574461d96ee708f58fe553049ad4f48bb983a").is_err());
        assert!(normalize_address("0x1234").is_err());
        assert!(normalize_address("0xzzc574461d96ee708f58fe553049ad4f48bb983a").is_err());
    }
}
