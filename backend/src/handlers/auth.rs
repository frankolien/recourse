use actix_web::http::{header, StatusCode};
use actix_web::{web, HttpRequest, HttpResponse};
use base64::Engine;
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;
use webauthn_rs::prelude::{
    Passkey, PasskeyAuthentication, PasskeyRegistration, PublicKeyCredential,
    RegisterPublicKeyCredential,
};

use crate::services::account_sessions;
use crate::services::apple_auth::AppleAuthService;
use crate::services::auth;
use crate::services::google_auth::GoogleAuthService;
use crate::services::passkey::PasskeyService;
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

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GoogleExchangeRequest {
    id_token: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EmailRegisterRequest {
    email: String,
    password: String,
    given_name: Option<String>,
    family_name: Option<String>,
}

#[derive(Deserialize)]
pub struct EmailLoginRequest {
    email: String,
    password: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasskeyRegisterStartRequest {
    email: String,
    given_name: Option<String>,
    family_name: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasskeyRegisterFinishRequest {
    challenge_id: String,
    credential: RegisterPublicKeyCredential,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasskeyLoginStartRequest {
    email: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PasskeyLoginFinishRequest {
    challenge_id: String,
    credential: PublicKeyCredential,
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

/// POST /api/auth/google - verify a Google Identity Services ID token and issue a Recourse
/// account session. Google's RS256-signed, audience-bound ID token is the proof; no server
/// nonce is needed.
pub async fn google_exchange(
    pool: web::Data<PgPool>,
    google: web::Data<Option<GoogleAuthService>>,
    body: web::Json<GoogleExchangeRequest>,
) -> HttpResponse {
    let Some(google) = google.get_ref().as_ref() else {
        return error_response(503, "Sign in with Google is not configured");
    };
    let identity = match google.verify_id_token(&body.id_token).await {
        Ok(identity) => identity,
        Err(error) => {
            tracing::warn!("Google token verification failed: {error:#}");
            return error_response(401, "Google sign-in could not be verified");
        }
    };
    match account_sessions::create_provider_session(
        pool.get_ref(),
        "google",
        identity.subject,
        identity.email,
        identity.given_name,
        identity.family_name,
    )
    .await
    {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("creating account session", error),
    }
}

/// POST /api/auth/email/register - create an email+password account and issue a session.
/// 409 if the email is already registered, 400 for a malformed email or short password.
pub async fn email_register(
    pool: web::Data<PgPool>,
    body: web::Json<EmailRegisterRequest>,
) -> HttpResponse {
    match account_sessions::register_email(
        pool.get_ref(),
        &body.email,
        &body.password,
        body.given_name.clone(),
        body.family_name.clone(),
    )
    .await
    {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("registering email account", error),
    }
}

/// POST /api/auth/email/login - verify an email+password pair and issue a session.
pub async fn email_login(
    pool: web::Data<PgPool>,
    body: web::Json<EmailLoginRequest>,
) -> HttpResponse {
    match account_sessions::login_email(pool.get_ref(), &body.email, &body.password).await {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("email login", error),
    }
}

/// POST /api/auth/passkey/register/start - begin a WebAuthn registration for an email. The
/// account is created only on finish; here we just check the email is free and hand back the
/// creation options plus a single-use challenge id.
pub async fn passkey_register_start(
    pool: web::Data<PgPool>,
    passkey: web::Data<Option<PasskeyService>>,
    body: web::Json<PasskeyRegisterStartRequest>,
) -> HttpResponse {
    let Some(service) = passkey.get_ref().as_ref() else {
        return error_response(503, "Passkeys are not configured");
    };
    let email = match account_sessions::normalize_email(&body.email) {
        Ok(email) => email,
        Err(error) => return account_error_response("passkey registration", error),
    };
    match account_sessions::passkey_account_id(pool.get_ref(), &email).await {
        Ok(Some(_)) => {
            return error_response(409, "a passkey is already registered for this email")
        }
        Ok(None) => {}
        Err(error) => return account_error_response("passkey registration", error),
    }

    let user_id = Uuid::new_v4();
    let display = display_name(
        body.given_name.as_deref(),
        body.family_name.as_deref(),
        &email,
    );
    let (challenge, state) = match service.start_registration(user_id, &email, &display, None) {
        Ok(pair) => pair,
        Err(error) => {
            tracing::warn!("passkey register start: {error:?}");
            return error_response(400, "could not start passkey registration");
        }
    };
    let state_json = match serde_json::to_value(&state) {
        Ok(value) => value,
        Err(error) => {
            tracing::error!("serializing passkey registration state: {error}");
            return error_response(500, "internal error");
        }
    };
    let challenge_id = account_sessions::new_challenge_id();
    if let Err(error) = account_sessions::store_webauthn_ceremony(
        pool.get_ref(),
        &challenge_id,
        "register",
        Some(&email),
        body.given_name.as_deref(),
        body.family_name.as_deref(),
        None,
        &state_json,
    )
    .await
    {
        return account_error_response("passkey registration", error);
    }
    match passkey_start_payload(&challenge, &challenge_id) {
        Ok(payload) => HttpResponse::Ok().json(payload),
        Err(error) => {
            tracing::error!("serializing passkey options: {error}");
            error_response(500, "internal error")
        }
    }
}

/// POST /api/auth/passkey/register/finish - verify the authenticator's attestation, create
/// the passkey account, store the credential, and issue a session.
pub async fn passkey_register_finish(
    pool: web::Data<PgPool>,
    passkey: web::Data<Option<PasskeyService>>,
    body: web::Json<PasskeyRegisterFinishRequest>,
) -> HttpResponse {
    let Some(service) = passkey.get_ref().as_ref() else {
        return error_response(503, "Passkeys are not configured");
    };
    let ceremony = match account_sessions::take_webauthn_ceremony(
        pool.get_ref(),
        &body.challenge_id,
        "register",
    )
    .await
    {
        Ok(ceremony) => ceremony,
        Err(error) => return account_error_response("passkey registration", error),
    };
    let Some(email) = ceremony.email else {
        return error_response(
            400,
            "passkey challenge is missing its registration identity",
        );
    };
    let state: PasskeyRegistration = match serde_json::from_value(ceremony.state) {
        Ok(state) => state,
        Err(error) => {
            tracing::error!("deserializing passkey registration state: {error}");
            return error_response(400, "invalid passkey challenge state");
        }
    };
    let credential = match service.finish_registration(&body.credential, &state) {
        Ok(credential) => credential,
        Err(error) => {
            tracing::warn!("passkey register finish: {error:?}");
            return error_response(400, "passkey registration could not be verified");
        }
    };
    let credential_id = credential.cred_id().as_ref().to_vec();
    let passkey_json = match serde_json::to_value(&credential) {
        Ok(value) => value,
        Err(error) => {
            tracing::error!("serializing passkey: {error}");
            return error_response(500, "internal error");
        }
    };
    match account_sessions::create_passkey_account(
        pool.get_ref(),
        &email,
        ceremony.given_name,
        ceremony.family_name,
        credential_id,
        passkey_json,
    )
    .await
    {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("creating passkey account", error),
    }
}

/// POST /api/auth/passkey/login/start - begin authentication for an email's registered
/// passkeys, returning the request options and a single-use challenge id.
pub async fn passkey_login_start(
    pool: web::Data<PgPool>,
    passkey: web::Data<Option<PasskeyService>>,
    body: web::Json<PasskeyLoginStartRequest>,
) -> HttpResponse {
    let Some(service) = passkey.get_ref().as_ref() else {
        return error_response(503, "Passkeys are not configured");
    };
    let account =
        match account_sessions::passkey_account_by_email(pool.get_ref(), &body.email).await {
            Ok(Some(account)) => account,
            Ok(None) => return error_response(404, "no passkey is registered for this email"),
            Err(error) => return account_error_response("passkey login", error),
        };
    let account_id = account.account.account_id;
    let credentials: Vec<Passkey> = account
        .passkeys
        .into_iter()
        .filter_map(|value| serde_json::from_value(value).ok())
        .collect();
    if credentials.is_empty() {
        return error_response(404, "no passkey is registered for this email");
    }
    let (challenge, state) = match service.start_authentication(&credentials) {
        Ok(pair) => pair,
        Err(error) => {
            tracing::warn!("passkey login start: {error:?}");
            return error_response(400, "could not start passkey authentication");
        }
    };
    let state_json = match serde_json::to_value(&state) {
        Ok(value) => value,
        Err(error) => {
            tracing::error!("serializing passkey authentication state: {error}");
            return error_response(500, "internal error");
        }
    };
    let challenge_id = account_sessions::new_challenge_id();
    if let Err(error) = account_sessions::store_webauthn_ceremony(
        pool.get_ref(),
        &challenge_id,
        "authenticate",
        None,
        None,
        None,
        Some(account_id),
        &state_json,
    )
    .await
    {
        return account_error_response("passkey login", error);
    }
    match passkey_start_payload(&challenge, &challenge_id) {
        Ok(payload) => HttpResponse::Ok().json(payload),
        Err(error) => {
            tracing::error!("serializing passkey options: {error}");
            error_response(500, "internal error")
        }
    }
}

/// POST /api/auth/passkey/login/finish - verify the assertion, bump the credential's
/// signature counter, and issue a session.
pub async fn passkey_login_finish(
    pool: web::Data<PgPool>,
    passkey: web::Data<Option<PasskeyService>>,
    body: web::Json<PasskeyLoginFinishRequest>,
) -> HttpResponse {
    let Some(service) = passkey.get_ref().as_ref() else {
        return error_response(503, "Passkeys are not configured");
    };
    let ceremony = match account_sessions::take_webauthn_ceremony(
        pool.get_ref(),
        &body.challenge_id,
        "authenticate",
    )
    .await
    {
        Ok(ceremony) => ceremony,
        Err(error) => return account_error_response("passkey login", error),
    };
    let Some(account_id) = ceremony.account_id else {
        return error_response(400, "passkey challenge is missing its account");
    };
    let state: PasskeyAuthentication = match serde_json::from_value(ceremony.state) {
        Ok(state) => state,
        Err(error) => {
            tracing::error!("deserializing passkey authentication state: {error}");
            return error_response(400, "invalid passkey challenge state");
        }
    };
    let result = match service.finish_authentication(&body.credential, &state) {
        Ok(result) => result,
        Err(error) => {
            tracing::warn!("passkey login finish: {error:?}");
            return error_response(401, "passkey authentication could not be verified");
        }
    };
    let account = match account_sessions::passkey_account_by_id(pool.get_ref(), account_id).await {
        Ok(Some(account)) => account,
        Ok(None) => return error_response(401, "passkey account no longer exists"),
        Err(error) => return account_error_response("passkey login", error),
    };
    // Persist the bumped signature counter for the credential that just authenticated.
    let mut updated: Option<(Vec<u8>, serde_json::Value)> = None;
    for value in &account.passkeys {
        let Ok(mut stored) = serde_json::from_value::<Passkey>(value.clone()) else {
            continue;
        };
        if let Some(true) = stored.update_credential(&result) {
            match serde_json::to_value(&stored) {
                Ok(json) => updated = Some((stored.cred_id().as_ref().to_vec(), json)),
                Err(error) => {
                    tracing::error!("serializing updated passkey: {error}");
                    return error_response(500, "internal error");
                }
            }
        }
    }
    match account_sessions::issue_passkey_login(pool.get_ref(), account.account, updated).await {
        Ok(grant) => HttpResponse::Ok().json(grant),
        Err(error) => account_error_response("passkey login", error),
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

// The WebAuthn options (CreationChallengeResponse / RequestChallengeResponse) already
// serialize to { "publicKey": {...} } for the platform authenticator API; we merge the
// correlation id in as a sibling so the client receives { publicKey: <options>, challengeId }.
fn passkey_start_payload(
    options: &impl serde::Serialize,
    challenge_id: &str,
) -> Result<serde_json::Value, serde_json::Error> {
    let mut value = serde_json::to_value(options)?;
    if let Some(object) = value.as_object_mut() {
        object.insert("challengeId".to_string(), json!(challenge_id));
    }
    Ok(value)
}

// The passkey's human-facing label: the person's name if we have it, else their email.
fn display_name(given: Option<&str>, family: Option<&str>, email: &str) -> String {
    let full = [given, family]
        .into_iter()
        .flatten()
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    if full.is_empty() {
        email.to_string()
    } else {
        full
    }
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
