use alloy::primitives::keccak256;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use serde::Serialize;
use sqlx::{PgPool, Postgres, Transaction};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::services::apple_auth::{sha256_hex, VerifiedAppleIdentity};

pub const APPLE_CHALLENGE_TTL_SECS: i64 = 300;
const ACCESS_TOKEN_TTL_SECS: i64 = 15 * 60;
const REFRESH_TOKEN_TTL_SECS: i64 = 30 * 24 * 60 * 60;

#[derive(Debug)]
pub enum AccountAuthError {
    Unauthorized(String),
    Internal(String),
}

impl AccountAuthError {
    pub fn parts(&self) -> (u16, String) {
        match self {
            Self::Unauthorized(message) => (401, message.clone()),
            Self::Internal(message) => (500, message.clone()),
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleChallenge {
    pub nonce: String,
    pub expires_at: i64,
    pub ttl_secs: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountProfile {
    pub account_id: i64,
    pub provider_user_id: String,
    pub email: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionGrant {
    pub access_token: String,
    pub refresh_token: String,
    pub access_expires_at: i64,
    pub refresh_expires_at: i64,
    pub account: AccountProfile,
}

pub async fn issue_apple_challenge(pool: &PgPool) -> Result<AppleChallenge, AccountAuthError> {
    let now = now_secs();
    let expires_at = now + APPLE_CHALLENGE_TTL_SECS;
    let nonce = random_token();
    let nonce_hash = token_hash(&nonce);

    let _ = sqlx::query("DELETE FROM apple_auth_challenges WHERE expires_at < $1")
        .bind(now)
        .execute(pool)
        .await;
    sqlx::query("INSERT INTO apple_auth_challenges (nonce_hash, expires_at) VALUES ($1, $2)")
        .bind(nonce_hash)
        .bind(expires_at)
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("issuing Apple challenge: {error}")))?;

    Ok(AppleChallenge {
        nonce,
        expires_at,
        ttl_secs: APPLE_CHALLENGE_TTL_SECS,
    })
}

pub async fn validate_apple_challenge(
    pool: &PgPool,
    nonce: &str,
) -> Result<String, AccountAuthError> {
    let found = sqlx::query_scalar::<_, bool>(
        "SELECT TRUE FROM apple_auth_challenges \
         WHERE nonce_hash = $1 AND consumed = FALSE AND expires_at > $2",
    )
    .bind(token_hash(nonce))
    .bind(now_secs())
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("checking Apple challenge: {error}")))?;

    if found.is_none() {
        return Err(AccountAuthError::Unauthorized(
            "Apple challenge is invalid, expired, or already used".into(),
        ));
    }
    Ok(sha256_hex(nonce))
}

pub async fn create_session(
    pool: &PgPool,
    nonce: &str,
    identity: VerifiedAppleIdentity,
    given_name: Option<String>,
    family_name: Option<String>,
) -> Result<SessionGrant, AccountAuthError> {
    let now = now_secs();
    let mut transaction = pool.begin().await.map_err(|error| {
        AccountAuthError::Internal(format!("starting auth transaction: {error}"))
    })?;

    consume_challenge(&mut transaction, nonce, now).await?;
    let account = upsert_account(
        &mut transaction,
        identity,
        clean_optional(given_name),
        clean_optional(family_name),
    )
    .await?;
    let grant = insert_session(&mut transaction, account, now).await?;

    transaction
        .commit()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("committing auth session: {error}")))?;
    Ok(grant)
}

pub async fn refresh_session(
    pool: &PgPool,
    refresh_token: &str,
) -> Result<SessionGrant, AccountAuthError> {
    let now = now_secs();
    let mut transaction = pool
        .begin()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("starting refresh: {error}")))?;
    let row = sqlx::query_as::<
        _,
        (
            i64,
            i64,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT s.session_id, a.account_id, a.apple_subject, a.email, a.given_name, a.family_name \
         FROM account_sessions s JOIN accounts a ON a.account_id = s.account_id \
         WHERE s.refresh_token_hash = $1 AND s.revoked_at IS NULL AND s.refresh_expires_at > $2 \
         FOR UPDATE",
    )
    .bind(token_hash(refresh_token))
    .bind(now)
    .fetch_optional(&mut *transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading refresh session: {error}")))?
    .ok_or_else(|| AccountAuthError::Unauthorized("refresh token is invalid or expired".into()))?;

    let account = AccountProfile {
        account_id: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
    };
    let access_token = random_token();
    let replacement_refresh_token = random_token();
    let access_expires_at = now + ACCESS_TOKEN_TTL_SECS;
    let refresh_expires_at = now + REFRESH_TOKEN_TTL_SECS;
    sqlx::query(
        "UPDATE account_sessions SET access_token_hash = $1, refresh_token_hash = $2, \
         access_expires_at = $3, refresh_expires_at = $4, updated_at = now() \
         WHERE session_id = $5",
    )
    .bind(token_hash(&access_token))
    .bind(token_hash(&replacement_refresh_token))
    .bind(access_expires_at)
    .bind(refresh_expires_at)
    .bind(row.0)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("rotating session: {error}")))?;
    transaction
        .commit()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("committing refresh: {error}")))?;

    Ok(SessionGrant {
        access_token,
        refresh_token: replacement_refresh_token,
        access_expires_at,
        refresh_expires_at,
        account,
    })
}

pub async fn account_for_access_token(
    pool: &PgPool,
    access_token: &str,
) -> Result<AccountProfile, AccountAuthError> {
    let row = sqlx::query_as::<_, (i64, String, Option<String>, Option<String>, Option<String>)>(
        "SELECT a.account_id, a.apple_subject, a.email, a.given_name, a.family_name \
         FROM account_sessions s JOIN accounts a ON a.account_id = s.account_id \
         WHERE s.access_token_hash = $1 AND s.revoked_at IS NULL AND s.access_expires_at > $2",
    )
    .bind(token_hash(access_token))
    .bind(now_secs())
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading account session: {error}")))?
    .ok_or_else(|| AccountAuthError::Unauthorized("access token is invalid or expired".into()))?;

    Ok(AccountProfile {
        account_id: row.0,
        provider_user_id: row.1,
        email: row.2,
        given_name: row.3,
        family_name: row.4,
    })
}

pub async fn revoke_access_token(
    pool: &PgPool,
    access_token: &str,
) -> Result<(), AccountAuthError> {
    sqlx::query(
        "UPDATE account_sessions SET revoked_at = now(), updated_at = now() \
         WHERE access_token_hash = $1 AND revoked_at IS NULL",
    )
    .bind(token_hash(access_token))
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("revoking session: {error}")))?;
    Ok(())
}

async fn consume_challenge(
    transaction: &mut Transaction<'_, Postgres>,
    nonce: &str,
    now: i64,
) -> Result<(), AccountAuthError> {
    let consumed = sqlx::query_scalar::<_, Vec<u8>>(
        "UPDATE apple_auth_challenges SET consumed = TRUE \
         WHERE nonce_hash = $1 AND consumed = FALSE AND expires_at > $2 \
         RETURNING nonce_hash",
    )
    .bind(token_hash(nonce))
    .bind(now)
    .fetch_optional(&mut **transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("consuming Apple challenge: {error}")))?;
    if consumed.is_none() {
        return Err(AccountAuthError::Unauthorized(
            "Apple challenge is invalid, expired, or already used".into(),
        ));
    }
    Ok(())
}

async fn upsert_account(
    transaction: &mut Transaction<'_, Postgres>,
    identity: VerifiedAppleIdentity,
    given_name: Option<String>,
    family_name: Option<String>,
) -> Result<AccountProfile, AccountAuthError> {
    let row = sqlx::query_as::<_, (i64, String, Option<String>, Option<String>, Option<String>)>(
        "INSERT INTO accounts (apple_subject, email, given_name, family_name) \
         VALUES ($1, $2, $3, $4) \
         ON CONFLICT (apple_subject) DO UPDATE SET \
           email = COALESCE(EXCLUDED.email, accounts.email), \
           given_name = COALESCE(EXCLUDED.given_name, accounts.given_name), \
           family_name = COALESCE(EXCLUDED.family_name, accounts.family_name), \
           updated_at = now() \
         RETURNING account_id, apple_subject, email, given_name, family_name",
    )
    .bind(identity.subject)
    .bind(identity.email)
    .bind(given_name)
    .bind(family_name)
    .fetch_one(&mut **transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("saving Apple account: {error}")))?;

    Ok(AccountProfile {
        account_id: row.0,
        provider_user_id: row.1,
        email: row.2,
        given_name: row.3,
        family_name: row.4,
    })
}

async fn insert_session(
    transaction: &mut Transaction<'_, Postgres>,
    account: AccountProfile,
    now: i64,
) -> Result<SessionGrant, AccountAuthError> {
    let access_token = random_token();
    let refresh_token = random_token();
    let access_expires_at = now + ACCESS_TOKEN_TTL_SECS;
    let refresh_expires_at = now + REFRESH_TOKEN_TTL_SECS;
    sqlx::query(
        "INSERT INTO account_sessions \
         (account_id, access_token_hash, refresh_token_hash, access_expires_at, refresh_expires_at) \
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(account.account_id)
    .bind(token_hash(&access_token))
    .bind(token_hash(&refresh_token))
    .bind(access_expires_at)
    .bind(refresh_expires_at)
    .execute(&mut **transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("creating account session: {error}")))?;

    Ok(SessionGrant {
        access_token,
        refresh_token,
        access_expires_at,
        refresh_expires_at,
        account,
    })
}

fn random_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

fn token_hash(token: &str) -> Vec<u8> {
    keccak256(token.as_bytes()).to_vec()
}

fn clean_optional(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_are_random_and_url_safe() {
        let first = random_token();
        let second = random_token();
        assert_ne!(first, second);
        assert_eq!(first.len(), 43);
        assert!(!first.contains('='));
    }
}
