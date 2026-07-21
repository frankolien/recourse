use actix_web::http::{header, StatusCode};
use actix_web::{web, HttpRequest, HttpResponse};
use base64::Engine;
use serde_json::json;
use sqlx::PgPool;

use crate::services::auth;
use crate::services::AppConfig;

// Buyer-signed authorization travels in this header as base64 JSON, keeping it out of the
// signed request body (the signature commits to the body, so it cannot contain itself).
pub const AUTH_HEADER: &str = "x-recourse-auth";

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
