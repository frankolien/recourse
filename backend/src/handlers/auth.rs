use actix_web::http::{header, StatusCode};
use actix_web::{web, HttpRequest, HttpResponse};
use base64::Engine;
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;

use crate::services::account_sessions;
use crate::services::apple_auth::AppleAuthService;
use crate::services::auth;
use crate::services::AppConfig;

// Buyer-signed authorization travels in this header as base64 JSON, keeping it out of the
// signed request body (the signature commits to the body, so it cannot contain itself).
pub const AUTH_HEADER: &str = "x-recourse-auth";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppleExchangeRequest {
    authorization_code: String,
    nonce: String,
    given_name: Option<String>,
    family_name: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    refresh_token: String,
}

/// POST /api/auth/challenge - issue a one-time nonce for wallet-signature auth. Public: a
/// nonce is worthless without a valid buyer signature over it, and it is single-use.
pub async fn challenge(pool: web::Data<PgPool>) -> HttpResponse {
    match auth::issue_challenge(pool.get_ref()).await {
        Ok(c) => HttpResponse::Ok().json(json!({
            "nonce": c.nonce,
            "expiresAt": c.expires_at,
            "ttlSecs": auth::CHALLENGE_TTL_SECS,
        })),
        Err(e) => {
            let (_, msg) = e.parts();
            tracing::error!("issue_challenge: {msg}");
            HttpResponse::InternalServerError().json(json!({ "error": "challenge failed" }))
        }
    }
}

/// POST /api/auth/apple/challenge - issue a server-owned nonce that the iPhone hashes
/// into ASAuthorizationAppleIDRequest.nonce. This binds Apple's credential to one
/// short-lived Recourse login attempt.
pub async fn apple_challenge(
    pool: web::Data<PgPool>,
    apple: web::Data<Option<AppleAuthService>>,
) -> HttpResponse {
    if apple.get_ref().is_none() {
        return error_response(503, "Sign in with Apple is not configured");
    }
    match account_sessions::issue_apple_challenge(pool.get_ref()).await {
        Ok(challenge) => HttpResponse::Ok().json(challenge),
        Err(error) => account_error_response("issuing Apple challenge", error),
    }
}

/// POST /api/auth/apple - exchange Apple's one-time authorization code, verify the
/// returned identity token and nonce, then issue opaque Recourse session tokens.
pub async fn apple_exchange(
    pool: web::Data<PgPool>,
    apple: web::Data<Option<AppleAuthService>>,
    body: web::Json<AppleExchangeRequest>,
) -> HttpResponse {
    let Some(apple) = apple.get_ref().as_ref() else {
        return error_response(503, "Sign in with Apple is not configured");
    };
    let expected_nonce_hash =
        match account_sessions::validate_apple_challenge(pool.get_ref(), &body.nonce).await {
            Ok(hash) => hash,
            Err(error) => return account_error_response("checking Apple challenge", error),
        };
    let identity = match apple
        .exchange_code(&body.authorization_code, &expected_nonce_hash)
        .await
    {
        Ok(identity) => identity,
        Err(error) => {
            tracing::warn!("Apple token exchange failed: {error:#}");
            return error_response(401, "Apple authorization could not be verified");
        }
    };

    match account_sessions::create_session(
        pool.get_ref(),
        &body.nonce,
        identity,
        body.given_name.clone(),
        body.family_name.clone(),
    )
    .await
    {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("creating account session", error),
    }
}

/// POST /api/auth/refresh - rotate both opaque tokens. A refresh token is single-use
/// because the stored hash is replaced atomically under a row lock.
pub async fn refresh(pool: web::Data<PgPool>, body: web::Json<RefreshRequest>) -> HttpResponse {
    match account_sessions::refresh_session(pool.get_ref(), &body.refresh_token).await {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("refreshing account session", error),
    }
}

/// GET /api/me - validate the short-lived access token and return the account profile.
pub async fn me(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(account) => HttpResponse::Ok().json(account),
        Err(error) => account_error_response("reading account session", error),
    }
}

/// POST /api/auth/logout - revoke the complete server session represented by this access
/// token. The iPhone separately deletes its Keychain copy.
pub async fn logout(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    match account_sessions::revoke_access_token(pool.get_ref(), token).await {
        Ok(()) => HttpResponse::NoContent().finish(),
        Err(error) => account_error_response("revoking account session", error),
    }
}

// Decode the X-Recourse-Auth envelope. Errors carry the HTTP status the caller should see.
pub fn extract_envelope(req: &HttpRequest) -> Result<auth::AuthEnvelope, (u16, String)> {
    let raw = req
        .headers()
        .get(AUTH_HEADER)
        .and_then(|v| v.to_str().ok())
        .ok_or((401, format!("missing {AUTH_HEADER} header")))?;
    let json = base64::engine::general_purpose::STANDARD
        .decode(raw.trim())
        .map_err(|_| (400, "auth header is not valid base64".to_string()))?;
    serde_json::from_slice::<auth::AuthEnvelope>(&json)
        .map_err(|e| (400, format!("auth envelope parse error: {e}")))
}

// Guard the privileged demo routes with a shared admin bearer token. Fails closed: with
// no ADMIN_API_KEY configured, no caller can reach settlement.
pub fn require_admin(req: &HttpRequest, config: &AppConfig) -> Result<(), (u16, String)> {
    let Some(key) = &config.admin_api_key else {
        return Err((
            503,
            "admin auth not configured; set ADMIN_API_KEY".to_string(),
        ));
    };
    let provided = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|s| s.strip_prefix("Bearer "));
    match provided {
        Some(p) if ct_eq(p.as_bytes(), key.as_bytes()) => Ok(()),
        _ => Err((401, "admin bearer token required".to_string())),
    }
}

fn bearer_token(req: &HttpRequest) -> Result<&str, (u16, String)> {
    req.headers()
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .filter(|value| !value.trim().is_empty())
        .ok_or((401, "bearer access token required".to_string()))
}

fn account_error_response(
    operation: &str,
    error: account_sessions::AccountAuthError,
) -> HttpResponse {
    let (status, message) = error.parts();
    if status >= 500 {
        tracing::error!("{operation}: {message}");
    }
    error_response(status, &message)
}

// Constant-time comparison so a wrong key cannot be recovered byte-by-byte from timing.
fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b) {
        diff |= x ^ y;
    }
    diff == 0
}

pub fn error_response(status: u16, message: &str) -> HttpResponse {
    let code = StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    HttpResponse::build(code).json(json!({ "error": message }))
}
