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
const WEBAUTHN_CEREMONY_TTL_SECS: i64 = 300;

#[derive(Debug)]
pub enum AccountAuthError {
    BadRequest(String),
    Unauthorized(String),
    Conflict(String),
    Internal(String),
}

impl AccountAuthError {
    pub fn parts(&self) -> (u16, String) {
        match self {
            Self::BadRequest(message) => (400, message.clone()),
            Self::Unauthorized(message) => (401, message.clone()),
            Self::Conflict(message) => (409, message.clone()),
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
    // Which social provider identifies this account ("apple" or "google").
    pub provider: String,
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
        "apple",
        identity.subject,
        identity.email,
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

// Session creation for a provider that verifies its own token (e.g. Google), without an
// Apple-style server challenge. The provider's ID token is the freshness and audience
// proof; here we only upsert the account and mint the opaque Recourse session tokens.
pub async fn create_provider_session(
    pool: &PgPool,
    provider: &str,
    subject: String,
    email: Option<String>,
    given_name: Option<String>,
    family_name: Option<String>,
) -> Result<SessionGrant, AccountAuthError> {
    let now = now_secs();
    let mut transaction = pool.begin().await.map_err(|error| {
        AccountAuthError::Internal(format!("starting auth transaction: {error}"))
    })?;

    let account = upsert_account(
        &mut transaction,
        provider,
        subject,
        email,
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

// Email/password registration. There is no social provider to vouch for identity here, so
// the account carries an Argon2id password hash (provider='email'). No verification email
// in this build: the address is trusted on submission. Arc wallet signatures still
// authorize payment writes, so this only affects familiar onboarding, not settlement.
pub async fn register_email(
    pool: &PgPool,
    email: &str,
    password: &str,
    given_name: Option<String>,
    family_name: Option<String>,
) -> Result<SessionGrant, AccountAuthError> {
    let email = normalize_email(email)?;
    validate_password(password)?;
    let password_hash = hash_password(password)?;
    let now = now_secs();

    let mut transaction = pool
        .begin()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("starting registration: {error}")))?;
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "INSERT INTO accounts (provider, provider_subject, email, given_name, family_name, password_hash) \
         VALUES ('email', $1, $1, $2, $3, $4) \
         RETURNING account_id, provider, provider_subject, email, given_name, family_name",
    )
    .bind(&email)
    .bind(clean_optional(given_name))
    .bind(clean_optional(family_name))
    .bind(&password_hash)
    .fetch_one(&mut *transaction)
    .await
    .map_err(registration_error)?;
    let account = AccountProfile {
        account_id: row.0,
        provider: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
    };
    let grant = insert_session(&mut transaction, account, now).await?;
    transaction
        .commit()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("committing registration: {error}")))?;
    Ok(grant)
}

// Email/password login. The error is uniform whether the email is unknown or the password
// is wrong, so the endpoint never reveals which addresses are registered.
pub async fn login_email(
    pool: &PgPool,
    email: &str,
    password: &str,
) -> Result<SessionGrant, AccountAuthError> {
    let email = normalize_email(email)?;
    let now = now_secs();
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT account_id, provider, provider_subject, email, given_name, family_name, password_hash \
         FROM accounts WHERE provider = 'email' AND provider_subject = $1",
    )
    .bind(&email)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading email account: {error}")))?;

    let invalid = || AccountAuthError::Unauthorized("invalid email or password".into());
    let row = row.ok_or_else(invalid)?;
    let hash = row.6.as_deref().ok_or_else(invalid)?;
    if !verify_password(password, hash) {
        return Err(invalid());
    }
    let account = AccountProfile {
        account_id: row.0,
        provider: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
    };
    let mut transaction = pool
        .begin()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("starting login: {error}")))?;
    let grant = insert_session(&mut transaction, account, now).await?;
    transaction
        .commit()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("committing login: {error}")))?;
    Ok(grant)
}

// ---- Passkeys (WebAuthn) ----
//
// A passkey login is an account (provider='passkey', provider_subject=lower(email)) that
// owns one or more stored WebAuthn credentials. The in-flight ceremony (the server's
// challenge state) is parked in webauthn_ceremonies, single-use and TTL-bound, so a
// challenge is good for exactly one finish.

/// Server state for one in-flight ceremony, returned when it is consumed.
pub struct WebauthnCeremony {
    pub email: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
    pub account_id: Option<i64>,
    pub state: serde_json::Value,
}

/// A passkey account with its stored credentials (the serialized webauthn-rs Passkey values).
pub struct PasskeyAccount {
    pub account: AccountProfile,
    pub passkeys: Vec<serde_json::Value>,
}

/// Opaque, single-use id handed to the client to correlate a ceremony's finish with its start.
pub fn new_challenge_id() -> String {
    random_token()
}

/// Park a ceremony's server state (serialized PasskeyRegistration/PasskeyAuthentication).
#[allow(clippy::too_many_arguments)]
pub async fn store_webauthn_ceremony(
    pool: &PgPool,
    challenge_id: &str,
    kind: &str,
    email: Option<&str>,
    given_name: Option<&str>,
    family_name: Option<&str>,
    account_id: Option<i64>,
    state: &serde_json::Value,
) -> Result<(), AccountAuthError> {
    let now = now_secs();
    let expires_at = now + WEBAUTHN_CEREMONY_TTL_SECS;
    let _ = sqlx::query("DELETE FROM webauthn_ceremonies WHERE expires_at < $1")
        .bind(now)
        .execute(pool)
        .await;
    sqlx::query(
        "INSERT INTO webauthn_ceremonies \
         (challenge_id, kind, email, given_name, family_name, account_id, state, expires_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(challenge_id)
    .bind(kind)
    .bind(email)
    .bind(given_name)
    .bind(family_name)
    .bind(account_id)
    .bind(state)
    .bind(expires_at)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("storing WebAuthn ceremony: {error}")))?;
    Ok(())
}

/// Consume a ceremony atomically (DELETE ... RETURNING): valid for exactly one finish, and
/// only if it is unexpired and of the expected kind.
pub async fn take_webauthn_ceremony(
    pool: &PgPool,
    challenge_id: &str,
    kind: &str,
) -> Result<WebauthnCeremony, AccountAuthError> {
    let row = sqlx::query_as::<
        _,
        (
            Option<String>,
            Option<String>,
            Option<String>,
            Option<i64>,
            serde_json::Value,
        ),
    >(
        "DELETE FROM webauthn_ceremonies \
         WHERE challenge_id = $1 AND kind = $2 AND expires_at > $3 \
         RETURNING email, given_name, family_name, account_id, state",
    )
    .bind(challenge_id)
    .bind(kind)
    .bind(now_secs())
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("consuming WebAuthn ceremony: {error}")))?
    .ok_or_else(|| {
        AccountAuthError::Unauthorized(
            "passkey challenge is invalid, expired, or already used".into(),
        )
    })?;
    Ok(WebauthnCeremony {
        email: row.0,
        given_name: row.1,
        family_name: row.2,
        account_id: row.3,
        state: row.4,
    })
}

/// Whether a passkey account already exists for this email (register guards against a second).
pub async fn passkey_account_id(
    pool: &PgPool,
    email: &str,
) -> Result<Option<i64>, AccountAuthError> {
    let email = normalize_email(email)?;
    sqlx::query_scalar::<_, i64>(
        "SELECT account_id FROM accounts WHERE provider = 'passkey' AND provider_subject = $1",
    )
    .bind(&email)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("looking up passkey account: {error}")))
}

/// Load a passkey account and its credentials by email (login start).
pub async fn passkey_account_by_email(
    pool: &PgPool,
    email: &str,
) -> Result<Option<PasskeyAccount>, AccountAuthError> {
    let email = normalize_email(email)?;
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT account_id, provider, provider_subject, email, given_name, family_name \
         FROM accounts WHERE provider = 'passkey' AND provider_subject = $1",
    )
    .bind(&email)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("loading passkey account: {error}")))?;
    let Some(row) = row else {
        return Ok(None);
    };
    let account = profile_from_row(row);
    let passkeys = load_passkeys(pool, account.account_id).await?;
    Ok(Some(PasskeyAccount { account, passkeys }))
}

/// Load a passkey account and its credentials by account id (login finish).
pub async fn passkey_account_by_id(
    pool: &PgPool,
    account_id: i64,
) -> Result<Option<PasskeyAccount>, AccountAuthError> {
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT account_id, provider, provider_subject, email, given_name, family_name \
         FROM accounts WHERE account_id = $1",
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("loading passkey account: {error}")))?;
    let Some(row) = row else {
        return Ok(None);
    };
    let account = profile_from_row(row);
    let passkeys = load_passkeys(pool, account_id).await?;
    Ok(Some(PasskeyAccount { account, passkeys }))
}

/// Create the passkey account, store its first credential, and issue a session (register finish).
pub async fn create_passkey_account(
    pool: &PgPool,
    email: &str,
    given_name: Option<String>,
    family_name: Option<String>,
    credential_id: Vec<u8>,
    passkey: serde_json::Value,
) -> Result<SessionGrant, AccountAuthError> {
    let email = normalize_email(email)?;
    let now = now_secs();
    let mut transaction = pool.begin().await.map_err(|error| {
        AccountAuthError::Internal(format!("starting passkey registration: {error}"))
    })?;
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "INSERT INTO accounts (provider, provider_subject, email, given_name, family_name) \
         VALUES ('passkey', $1, $1, $2, $3) \
         RETURNING account_id, provider, provider_subject, email, given_name, family_name",
    )
    .bind(&email)
    .bind(clean_optional(given_name))
    .bind(clean_optional(family_name))
    .fetch_one(&mut *transaction)
    .await
    .map_err(registration_error)?;
    let account = profile_from_row(row);
    sqlx::query(
        "INSERT INTO passkey_credentials (account_id, credential_id, passkey) VALUES ($1, $2, $3)",
    )
    .bind(account.account_id)
    .bind(&credential_id)
    .bind(&passkey)
    .execute(&mut *transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("storing passkey credential: {error}")))?;
    let grant = insert_session(&mut transaction, account, now).await?;
    transaction.commit().await.map_err(|error| {
        AccountAuthError::Internal(format!("committing passkey registration: {error}"))
    })?;
    Ok(grant)
}

/// Issue a session for an existing passkey account, optionally persisting a bumped signature
/// counter for the credential that just authenticated (login finish).
pub async fn issue_passkey_login(
    pool: &PgPool,
    account: AccountProfile,
    updated_credential: Option<(Vec<u8>, serde_json::Value)>,
) -> Result<SessionGrant, AccountAuthError> {
    let now = now_secs();
    let mut transaction = pool
        .begin()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("starting passkey login: {error}")))?;
    if let Some((credential_id, passkey)) = updated_credential {
        sqlx::query("UPDATE passkey_credentials SET passkey = $1 WHERE credential_id = $2")
            .bind(&passkey)
            .bind(&credential_id)
            .execute(&mut *transaction)
            .await
            .map_err(|error| {
                AccountAuthError::Internal(format!("updating passkey counter: {error}"))
            })?;
    }
    let grant = insert_session(&mut transaction, account, now).await?;
    transaction.commit().await.map_err(|error| {
        AccountAuthError::Internal(format!("committing passkey login: {error}"))
    })?;
    Ok(grant)
}

async fn load_passkeys(
    pool: &PgPool,
    account_id: i64,
) -> Result<Vec<serde_json::Value>, AccountAuthError> {
    sqlx::query_scalar::<_, serde_json::Value>(
        "SELECT passkey FROM passkey_credentials WHERE account_id = $1",
    )
    .bind(account_id)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("loading passkeys: {error}")))
}

fn profile_from_row(
    row: (
        i64,
        String,
        String,
        Option<String>,
        Option<String>,
        Option<String>,
    ),
) -> AccountProfile {
    AccountProfile {
        account_id: row.0,
        provider: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
    }
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
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "SELECT s.session_id, a.account_id, a.provider, a.provider_subject, a.email, a.given_name, a.family_name \
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
        provider: row.2,
        provider_user_id: row.3,
        email: row.4,
        given_name: row.5,
        family_name: row.6,
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
    let row = sqlx::query_as::<_, (i64, String, String, Option<String>, Option<String>, Option<String>)>(
        "SELECT a.account_id, a.provider, a.provider_subject, a.email, a.given_name, a.family_name \
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
        provider: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
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
    provider: &str,
    subject: String,
    email: Option<String>,
    given_name: Option<String>,
    family_name: Option<String>,
) -> Result<AccountProfile, AccountAuthError> {
    let row = sqlx::query_as::<
        _,
        (
            i64,
            String,
            String,
            Option<String>,
            Option<String>,
            Option<String>,
        ),
    >(
        "INSERT INTO accounts (provider, provider_subject, email, given_name, family_name) \
         VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (provider, provider_subject) DO UPDATE SET \
           email = COALESCE(EXCLUDED.email, accounts.email), \
           given_name = COALESCE(EXCLUDED.given_name, accounts.given_name), \
           family_name = COALESCE(EXCLUDED.family_name, accounts.family_name), \
           updated_at = now() \
         RETURNING account_id, provider, provider_subject, email, given_name, family_name",
    )
    .bind(provider)
    .bind(subject)
    .bind(email)
    .bind(given_name)
    .bind(family_name)
    .fetch_one(&mut **transaction)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("saving {provider} account: {error}")))?;

    Ok(AccountProfile {
        account_id: row.0,
        provider: row.1,
        provider_user_id: row.2,
        email: row.3,
        given_name: row.4,
        family_name: row.5,
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

pub(crate) fn normalize_email(email: &str) -> Result<String, AccountAuthError> {
    let email = email.trim().to_lowercase();
    // Minimal structural check only; deliverability is out of scope (no verification email
    // in this build). The client is expected to validate more strictly before submitting.
    let valid =
        email.len() >= 3 && email.contains('@') && !email.starts_with('@') && !email.ends_with('@');
    if !valid {
        return Err(AccountAuthError::BadRequest(
            "a valid email address is required".into(),
        ));
    }
    Ok(email)
}

fn validate_password(password: &str) -> Result<(), AccountAuthError> {
    if password.len() < 8 {
        return Err(AccountAuthError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    Ok(())
}

// Argon2id with a fresh random salt, encoded as a self-describing PHC string. Note this
// runs on the async worker; at demo scale that is fine, but a high-traffic deployment would
// offload it to a blocking pool.
fn hash_password(password: &str) -> Result<String, AccountAuthError> {
    use argon2::password_hash::{PasswordHasher, SaltString};
    use argon2::Argon2;

    let mut salt_bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut salt_bytes);
    let salt = SaltString::encode_b64(&salt_bytes)
        .map_err(|error| AccountAuthError::Internal(format!("building password salt: {error}")))?;
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|error| AccountAuthError::Internal(format!("hashing password: {error}")))
}

fn verify_password(password: &str, hash: &str) -> bool {
    use argon2::password_hash::{PasswordHash, PasswordVerifier};
    use argon2::Argon2;

    match PasswordHash::new(hash) {
        Ok(parsed) => Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok(),
        Err(_) => false,
    }
}

// A duplicate (provider, provider_subject) means the email is already registered; surface
// that as a 409 rather than a generic 500.
fn registration_error(error: sqlx::Error) -> AccountAuthError {
    if let sqlx::Error::Database(db) = &error {
        if db.code().as_deref() == Some("23505") {
            return AccountAuthError::Conflict("an account with this email already exists".into());
        }
    }
    AccountAuthError::Internal(format!("creating email account: {error}"))
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

    #[test]
    fn password_hash_roundtrips() {
        let hash = hash_password("correct horse battery staple").unwrap();
        // A self-describing Argon2 PHC string, never the plaintext.
        assert!(hash.starts_with("$argon2"));
        assert!(!hash.contains("correct horse"));
        assert!(verify_password("correct horse battery staple", &hash));
        assert!(!verify_password("wrong password", &hash));
    }

    #[test]
    fn email_normalization_and_validation() {
        assert_eq!(
            normalize_email("  Buyer@Example.COM ").unwrap(),
            "buyer@example.com"
        );
        assert!(normalize_email("not-an-email").is_err());
        assert!(normalize_email("@nope.com").is_err());
        assert!(validate_password("7chars!").is_err());
        assert!(validate_password("8chars!!").is_ok());
    }
}
