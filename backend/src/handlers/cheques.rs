use actix_web::{web, HttpRequest, HttpResponse};
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::{account_sessions, cheques};

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

/// POST /api/cheques - store a signed cheque so its recipient can find it.
pub async fn write_cheque(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    let cheque: cheques::NewCheque = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(error) => return error_response(400, &format!("invalid cheque body: {error}")),
    };

    match cheques::create(pool.get_ref(), account_id, cheque).await {
        Ok(stored) => HttpResponse::Created().json(stored),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// GET /api/cheques/outbox - cheques this account wrote.
pub async fn outbox(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    match cheques::written_by(pool.get_ref(), account_id).await {
        Ok(list) => HttpResponse::Ok().json(list),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// GET /api/cheques/inbox - cheques written to this account.
///
/// Empty rather than an error for an account that has never put an address on file:
/// nobody could have written it a cheque, because nothing published where to send one.
pub async fn inbox(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    match cheques::written_to(pool.get_ref(), account_id).await {
        Ok(list) => HttpResponse::Ok().json(list),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}
