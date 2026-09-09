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
pub struct AbandonBody {
    pub grant_id: String,
}

/// POST /api/me/account/abandon - give up a wallet whose keys are gone, so the
/// account can make a new one. The grant from the emailed code is the proof.
pub async fn abandon(pool: web::Data<PgPool>, req: HttpRequest, body: web::Json<AbandonBody>) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::abandon_wallet(pool.get_ref(), profile.account_id, &body.grant_id).await {
        Ok(()) => HttpResponse::Ok().json(serde_json::json!({ "ok": true })),
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
    push: web::Data<Option<std::sync::Arc<crate::services::push::Push>>>,
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
        Ok(plan) => {
            warn_of_recovery(pool.get_ref(), push.get_ref(), profile.account_id, "device", plan.ready_at).await;
            HttpResponse::Ok().json(plan)
        }
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

/// Tell the account a key change has been scheduled. This is what the delay is for:
/// a wait nobody hears about protects nobody. The message names the key and the hour,
/// and its route opens the screen with the stop button on it.
async fn warn_of_recovery(
    pool: &PgPool,
    push: &Option<std::sync::Arc<crate::services::push::Push>>,
    account_id: i64,
    kind: &str,
    ready_at: chrono::DateTime<chrono::Utc>,
) {
    let Some(push) = push else { return };
    let what = if kind == "cloud" { "iCloud key" } else { "phone key" };
    push.notify(
        pool,
        &[account_id],
        "Someone is recovering your account",
        &format!("Your {what} is being replaced. If this is not you, stop it now."),
        serde_json::json!({ "kind": "recovery", "recoveryKind": kind, "readyAt": ready_at.to_rfc3339() }),
    )
    .await;
    tracing::info!("recovery: account {account_id} scheduled a {kind} key change, ready {ready_at}");
}

// Recovering a lost Cloud Key. The phone is still here and its Device Key still
// signs, so the pair that does this is Device plus Recovery. It waits a day, and the
// old Cloud Key can stop it in that time, which is the point of the wait.

/// POST /api/me/account/recovery/cloud/code
pub async fn cloud_recovery_code(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::issue_cloud_recovery_code(
        pool.get_ref(),
        service.get_ref(),
        profile.account_id,
        profile.email.as_deref(),
    )
    .await
    {
        Ok(issued) => HttpResponse::Ok().json(issued),
        Err(error) => failed(error),
    }
}

/// POST /api/me/account/recovery/cloud/verify
pub async fn cloud_recovery_verify(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    body: web::Json<VerifyBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::verify_cloud_recovery_code(pool.get_ref(), profile.account_id, &body.code).await {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudRotationBody {
    pub grant_id: String,
    pub new_cloud_owner: String,
}

/// POST /api/me/account/recovery/cloud/prepare - park the swap and start the clock.
pub async fn cloud_recovery_prepare(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    push: web::Data<Option<std::sync::Arc<crate::services::push::Push>>>,
    req: HttpRequest,
    body: web::Json<CloudRotationBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    let new_cloud = match parse_address("newCloudOwner", &body.new_cloud_owner) {
        Ok(address) => address,
        Err(response) => return response,
    };
    match smart_accounts::prepare_cloud_rotation(
        pool.get_ref(),
        service.get_ref(),
        profile.account_id,
        &body.grant_id,
        new_cloud,
    )
    .await
    {
        Ok(plan) => {
            warn_of_recovery(pool.get_ref(), push.get_ref(), profile.account_id, "cloud", plan.ready_at).await;
            HttpResponse::Ok().json(plan)
        }
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RotationIdBody {
    pub rotation_id: i64,
}

/// POST /api/me/account/recovery/cloud/signature - the Recovery Key's half, once the
/// day is up. Refused earlier, and refused for good once anyone has stopped it.
pub async fn cloud_recovery_signature(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
    body: web::Json<RotationIdBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::cloud_rotation_signature(
        pool.get_ref(),
        service.get_ref(),
        profile.account_id,
        body.rotation_id,
    )
    .await
    {
        Ok(signature) => HttpResponse::Ok().json(serde_json::json!({ "signature": signature })),
        Err(error) => failed(error),
    }
}

/// POST /api/me/account/recovery/cloud/settle - the phone reporting its swap landed.
/// Checked against the Safe's own owner list before anything here is believed.
pub async fn cloud_recovery_settle(
    pool: web::Data<PgPool>,
    service: web::Data<SmartAccounts>,
    req: HttpRequest,
    body: web::Json<RotationIdBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::settle_cloud_rotation(pool.get_ref(), service.get_ref(), profile.account_id, body.rotation_id)
        .await
    {
        Ok(true) => HttpResponse::Ok().json(serde_json::json!({ "settled": true })),
        Ok(false) => error_response(409, "the Safe does not have that key yet"),
        Err(error) => failed(error),
    }
}

/// GET /api/me/account/recovery/pending - what is waiting, so it can be stopped.
pub async fn recovery_pending(pool: web::Data<PgPool>, req: HttpRequest) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::pending_recoveries(pool.get_ref(), profile.account_id).await {
        Ok(list) => HttpResponse::Ok().json(list),
        Err(error) => failed(error),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CancelBody {
    pub kind: String,
    pub rotation_id: i64,
}

/// POST /api/me/account/recovery/cancel - stop a scheduled key change.
pub async fn recovery_cancel(
    pool: web::Data<PgPool>,
    req: HttpRequest,
    body: web::Json<CancelBody>,
) -> HttpResponse {
    let profile = match caller(pool.get_ref(), &req).await {
        Ok(profile) => profile,
        Err(response) => return response,
    };
    match smart_accounts::cancel_recovery(pool.get_ref(), profile.account_id, &body.kind, body.rotation_id).await {
        Ok(true) => HttpResponse::Ok().json(serde_json::json!({ "cancelled": true })),
        Ok(false) => error_response(409, "there is nothing waiting to stop"),
        Err(error) => failed(error),
    }
}
