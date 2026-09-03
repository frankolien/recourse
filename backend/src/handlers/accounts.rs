use actix_web::{web, HttpRequest, HttpResponse};
use alloy::primitives::{Address, U256};
use serde::Deserialize;
use sqlx::PgPool;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::account_sessions::{self, AccountProfile};
use crate::services::smart_accounts::{self, SmartAccounts};

/// Resolve the caller, or the response explaining why not. Session first, body second,
/// so a caller without a valid token always sees 401 rather than a parse error.
async fn caller(pool: &PgPool, req: &HttpRequest) -> Result<AccountProfile, HttpResponse> {
    let token = match bearer_token(req) {
        Ok(token) => token,
        Err((status, message)) => return Err(error_response(status, &message)),
    };
    account_sessions::account_for_access_token(pool, token)
        .await
        .map_err(|error| account_error_response("reading account session", error))
}

fn failed(error: account_sessions::AccountAuthError) -> HttpResponse {
    let (status, message) = error.parts();
    error_response(status, &message)
}

/// A P-256 public key as the phone reports it: two 32-byte coordinates, hex.
#[derive(Debug, Deserialize)]
pub struct DeviceKeyBody {
    pub x: String,
    pub y: String,
}

fn parse_coordinate(name: &str, value: &str) -> Result<U256, HttpResponse> {
    let digits = value.trim().trim_start_matches("0x");
    if digits.len() != 64 || !digits.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(error_response(400, &format!("device key {name} must be 32 bytes of hex")));
    }
    U256::from_str_radix(digits, 16).map_err(|_| error_response(400, &format!("device key {name} is not a number")))
}

fn parse_address(name: &str, value: &str) -> Result<Address, HttpResponse> {
    value
        .trim()
        .parse()
        .map_err(|_| error_response(400, &format!("{name} is not an address")))
}

/// GET /api/me/account - the account's Safe, if it has one.
pub async fn current(pool: web::Data<PgPool>, service: web::Data<SmartAccounts>, req: HttpRequest) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::current(pool.get_ref(), service.get_ref(), profile.account_id).await {
        Ok(Some(view)) => HttpResponse::Ok().json(view),
        // Every fresh install asks this, so "no account yet" is an ordinary answer.
        Ok(None) => error_response(404, "no smart account yet"),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProvisionBody {
    pub cloud_owner: String,
    pub device_key: DeviceKeyBody,
}

/// POST /api/me/account/provision - create the Safe for the two keys this phone holds.
pub async fn provision(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
    body: web::Json<ProvisionBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    let cloud_owner = match parse_address("cloudOwner", &body.cloud_owner) {
        Ok(address) => address,
        Err(response) => return response,
    };
    let (x, y) = match (
        parse_coordinate("x", &body.device_key.x),
        parse_coordinate("y", &body.device_key.y),
    ) {
        (Ok(x), Ok(y)) => (x, y),
        (Err(response), _) | (_, Err(response)) => return response,
    };

    match smart_accounts::provision(pool.get_ref(), service.get_ref(), profile.account_id, cloud_owner, x, y).await {
        Ok(view) => HttpResponse::Ok().json(view),
        Err(error) => failed(error),
    }
}

/// POST /api/me/account/recovery/code - email a code that opens a device swap.
pub async fn recovery_code(pool: web::Data<PgPool>, service: web::Data<SmartAccounts>, req: HttpRequest) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::issue_recovery_code(pool.get_ref(), service.get_ref(), profile.account_id, profile.email.as_deref())
        .await
    {
        Ok(issued) => HttpResponse::Ok().json(issued),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
pub struct VerifyBody {
    pub code: String,
}

/// POST /api/me/account/recovery/verify - trade the code for a short-lived grant.
pub async fn recovery_verify(pool: web::Data<PgPool>, req: HttpRequest, body: web::Json<VerifyBody>) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::verify_recovery_code(pool.get_ref(), profile.account_id, &body.code).await {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrepareBody {
    pub grant_id: String,
    pub device_key: DeviceKeyBody,
}

/// POST /api/me/account/device/prepare - stage the swap to this phone's new key.
pub async fn device_prepare(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
    body: web::Json<PrepareBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    let (x, y) = match (
        parse_coordinate("x", &body.device_key.x),
        parse_coordinate("y", &body.device_key.y),
    ) {
        (Ok(x), Ok(y)) => (x, y),
        (Err(response), _) | (_, Err(response)) => return response,
    };
    match smart_accounts::prepare_rotation(pool.get_ref(), service.get_ref(), profile.account_id, &body.grant_id, x, y).await {
        Ok(plan) => HttpResponse::Ok().json(plan),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecuteBody {
    pub rotation_id: i64,
    /// The Cloud Key's 65-byte signature over the staged hash, hex.
    pub cloud_signature: String,
}

/// POST /api/me/account/device/execute - add the Recovery Key and submit the swap.
pub async fn device_execute(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
    body: web::Json<ExecuteBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    let digits = body.cloud_signature.trim().trim_start_matches("0x");
    let bytes = match alloy::hex::decode(digits) {
        Ok(bytes) if bytes.len() == 65 => bytes,
        _ => return error_response(400, "cloudSignature must be 65 bytes of hex"),
    };
    let mut signature = [0u8; 65];
    signature.copy_from_slice(&bytes);

    match smart_accounts::execute_rotation(pool.get_ref(), service.get_ref(), profile.account_id, body.rotation_id, signature)
        .await
    {
        Ok(outcome) => HttpResponse::Ok().json(outcome),
        Err(error) => failed(error),
    }
}
