use actix_web::{web, HttpRequest, HttpResponse};
use serde::Deserialize;
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::{account_sessions, handles};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClaimHandleRequest {
    pub handle: String,
    pub address: String,
}

/// GET /api/handles/{handle} - who money goes to when someone types @name.
///
/// Deliberately unauthenticated. A sender may be using any wallet, and making them
/// hold a Recourse account before they can pay a Recourse user would be a worse
/// experience than the 0x string this replaces.
pub async fn resolve_handle(pool: web::Data<PgPool>, path: web::Path<String>) -> HttpResponse {
    match handles::resolve(pool.get_ref(), &path.into_inner()).await {
        Ok(handle) => HttpResponse::Ok().json(handle),
        Err(error) => {
            let (status, message) = error.parts();
            // An unclaimed name is a 404 rather than a 400: the client uses this same
            // call to offer the name to whoever asked for it.
            let status = if message == "no such handle" {
                404
            } else {
                status
            };
            error_response(status, &message)
        }
    }
}

/// A cap on one request, so a caller cannot ask the directory to scan itself.
const MAX_NAME_LOOKUP: usize = 50;

#[derive(Deserialize)]
pub struct NamesRequest {
    pub addresses: Vec<String>,
}

/// POST /api/handles/names - names for a batch of addresses.
///
/// A POST despite being a read, because the input is a list and a query string of
/// fifty addresses is a URL nobody should have to debug.
pub async fn names(pool: web::Data<PgPool>, body: web::Bytes) -> HttpResponse {
    let request: NamesRequest = match serde_json::from_slice(&body) {
        Ok(value) => value,
        Err(error) => return error_response(400, &format!("invalid names body: {error}")),
    };
    if request.addresses.len() > MAX_NAME_LOOKUP {
        return error_response(
            400,
            &format!("at most {MAX_NAME_LOOKUP} addresses per request"),
        );
    }

    match handles::names_for(pool.get_ref(), &request.addresses).await {
        Ok(found) => HttpResponse::Ok().json(found),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// PUT /api/me/handle - claim a handle, or point an existing one at a new address.
///
/// The address is supplied by the caller rather than read from a session, because the
/// server never holds a wallet key and has nothing else to go on. The account owns the
/// name; the name points wherever that account says it does.
pub async fn claim_handle(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    // Session first, body second, so a caller without a valid token always sees 401
    // rather than a parse error that reveals the shape of the request.
    let account = match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(account) => account,
        Err(error) => return account_error_response("reading account session", error),
    };
    let body: ClaimHandleRequest = match serde_json::from_slice(&body) {
        Ok(body) => body,
        Err(error) => return error_response(400, &format!("invalid handle body: {error}")),
    };

    match handles::claim(
        pool.get_ref(),
        account.account_id,
        &body.handle,
        &body.address,
    )
    .await
    {
        Ok(handle) => HttpResponse::Ok().json(handle),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}

/// GET /api/me/handle - the signed-in account's own handle, or 404 if unclaimed.
pub async fn my_handle(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    let account = match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(account) => account,
        Err(error) => return account_error_response("reading account session", error),
    };

    match handles::for_account(pool.get_ref(), account.account_id).await {
        Ok(Some(handle)) => HttpResponse::Ok().json(handle),
        Ok(None) => error_response(404, "no handle claimed"),
        Err(error) => {
            let (status, message) = error.parts();
            error_response(status, &message)
        }
    }
}
