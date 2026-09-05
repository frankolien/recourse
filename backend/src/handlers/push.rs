use actix_web::{web, HttpRequest, HttpResponse};
use serde::Deserialize;
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::account_sessions;

#[derive(Debug, Deserialize)]
pub struct TokenBody {
    pub token: String,
    /// sandbox or production, as the phone's build knows it.
    pub environment: String,
}

/// PUT /api/me/push-token - this phone wants to hear about its treasuries.
pub async fn register(pool: web::Data<PgPool>, req: HttpRequest, body: web::Json<TokenBody>) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    let profile = match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(profile) => profile,
        Err(error) => return account_error_response("reading account session", error),
    };
    let device = body.token.trim().to_lowercase();
    if device.is_empty() || device.len() > 512 || !device.chars().all(|c| c.is_ascii_hexdigit()) {
        return error_response(400, "token must be the device token as hex");
    }
    let environment = match body.environment.as_str() {
        "sandbox" | "production" => body.environment.as_str(),
        _ => return error_response(400, "environment must be sandbox or production"),
    };
    let saved = sqlx::query(
        "INSERT INTO push_devices (token, account_id, environment) VALUES ($1, $2, $3)
         ON CONFLICT (token) DO UPDATE SET account_id = EXCLUDED.account_id, environment = EXCLUDED.environment, updated_at = now()",
    )
    .bind(&device)
    .bind(profile.account_id)
    .bind(environment)
    .execute(pool.get_ref())
    .await;
    match saved {
        Ok(_) => {
            tracing::info!("push: account {} registered a {environment} device", profile.account_id);
            HttpResponse::Ok().json(serde_json::json!({ "ok": true }))
        }
        Err(error) => error_response(500, &format!("saving the token: {error}")),
    }
}

/// DELETE /api/me/push-token - this phone no longer wants alerts, or signed out.
pub async fn unregister(pool: web::Data<PgPool>, req: HttpRequest, body: web::Json<TokenBody>) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    let profile = match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(profile) => profile,
        Err(error) => return account_error_response("reading account session", error),
    };
    let removed = sqlx::query("DELETE FROM push_devices WHERE token = $1 AND account_id = $2")
        .bind(body.token.trim().to_lowercase())
        .bind(profile.account_id)
        .execute(pool.get_ref())
        .await;
    match removed {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({ "ok": true })),
        Err(error) => error_response(500, &format!("removing the token: {error}")),
    }
}
