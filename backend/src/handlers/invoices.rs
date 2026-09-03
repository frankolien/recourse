use actix_web::{web, HttpRequest, HttpResponse};
use serde::Deserialize;
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::{account_sessions, invoices};

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

fn failed(error: crate::services::account_sessions::AccountAuthError) -> HttpResponse {
    let (status, message) = error.parts();
    error_response(status, &message)
}

/// POST /api/invoices - ask someone for money on terms you have fixed.
pub async fn issue(pool: web::Data<PgPool>, req: HttpRequest, body: web::Bytes) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    let invoice: invoices::NewInvoice = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(error) => return error_response(400, &format!("invalid invoice body: {error}")),
    };

    match invoices::create(pool.get_ref(), account_id, invoice).await {
        Ok(stored) => HttpResponse::Created().json(stored),
        Err(error) => failed(error),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SignInvoiceRequest {
    pub signature: String,
}

/// POST /api/invoices/{id}/sign - answer an invoice addressed to you.
///
/// The signature is the payment. Nothing moves when this lands: it moves when the
/// issuer submits the authorization, which they can do at any point before the invoice
/// expires.
pub async fn sign(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    path: web::Path<i64>,
    body: web::Bytes,
) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    let request: SignInvoiceRequest = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(error) => return error_response(400, &format!("invalid signature body: {error}")),
    };

    match invoices::sign(
        pool.get_ref(),
        account_id,
        path.into_inner(),
        &request.signature,
    )
    .await
    {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(error) => failed(error),
    }
}

/// POST /api/invoices/{id}/cancel - withdraw a request nobody has answered.
pub async fn cancel(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    path: web::Path<i64>,
) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    match invoices::cancel(pool.get_ref(), account_id, path.into_inner()).await {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(error) => failed(error),
    }
}

/// GET /api/invoices/outbox - what you have asked others for.
pub async fn outbox(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    match invoices::issued_by(pool.get_ref(), account_id).await {
        Ok(list) => HttpResponse::Ok().json(list),
        Err(error) => failed(error),
    }
}

/// GET /api/invoices/inbox - what others have asked of you.
pub async fn inbox(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let account_id = match account_id(pool.get_ref(), &req).await {
        Ok(id) => id,
        Err(response) => return response,
    };
    match invoices::addressed_to(pool.get_ref(), account_id).await {
        Ok(list) => HttpResponse::Ok().json(list),
        Err(error) => failed(error),
    }
}
