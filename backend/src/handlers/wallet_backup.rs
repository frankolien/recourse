use actix_web::{web, HttpRequest, HttpResponse};
use serde_json::Value;
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::{account_sessions, wallet_backups};

/// Resolve the caller's account, or the response explaining why not.
///
/// Session first and body second throughout this module, so a caller without a valid
/// token always sees 401 rather than a parse error describing the request shape.
async fn account_id(pool: &PgPool, req: &HttpRequest) -> Result<i64, HttpResponse> {
    let token = match bearer_token(req) {
        Ok(token) => token,
        Err((status, message)) => return Err(error_response(status, &message)),
    };
    match account_sessions::account_for_access_token(pool, token).await {
        Ok(account) => Ok(account.account_id),
        Err(error) => Err(account_error_response("reading account session", error)),
    }
}

/// PUT /api/me/wallet-backup - store the sealed envelope for this account.
///
/// The body is ciphertext the server cannot read. It is validated structurally only,
/// because a blob that is obviously unopenable should fail here rather than on the new
/// phone, when there is no other copy of the key left.
pub async fn put_backup(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    let envelope: Value = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(error) => return error_response(400, &format!("invalid backup body: {error}")),
    };

    match wallet_backups::put(pool.get_ref(), account_id, envelope).await {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// GET /api/me/wallet-backup - fetch it back on a new device.
pub async fn get_backup(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };

    match wallet_backups::get(pool.get_ref(), account_id).await {
        Ok(Some(stored)) => HttpResponse::Ok().json(stored),
        // The app asks this on every fresh install, so "no backup" is an ordinary
        // answer rather than a failure.
        Ok(None) => error_response(404, "no backup stored"),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// DELETE /api/me/wallet-backup - turn recovery off.
///
/// The device keeps its key, so this stops the account carrying the wallet forward
/// rather than destroying the wallet.
pub async fn delete_backup(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };

    match wallet_backups::delete(pool.get_ref(), account_id).await {
        Ok(()) => HttpResponse::NoContent().finish(),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}
