pub mod account_sessions;
pub mod apple_auth;
pub mod attestor;
pub mod auth;
pub mod chain;
pub mod evidence;
pub mod google_auth;
pub mod passkey;

use alloy::primitives::Address;
use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::PathBuf;

// Addresses come only from deployments/arc-testnet.json (R3), never hardcoded. Some
// fields are unused until the vault indexer lands; kept so the parsed shape documents
// the full deployment.
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
pub struct Deployment {
    pub escrow: Address,
    #[serde(rename = "policyRegistry")]
    pub policy_registry: Address,
    #[serde(rename = "settlementVault")]
    pub settlement_vault: Address,
    #[serde(rename = "yieldAdapter")]
    pub yield_adapter: Address,
    pub usdc: Address,
    #[serde(rename = "chainId")]
    pub chain_id: u64,
}

#[derive(Debug, Clone)]
pub struct AppConfig {
    pub database_url: String,
    pub rpc_url: String,
    pub port: u16,
    pub index_interval_secs: u64,
    pub demo_mode: bool,
    pub escrow: Address,
    pub policy_registry: Address,
    pub chain_id: u64,
    // Attestor signing key (testnet throwaway, R7). Only consumed when DEMO_MODE is on
    // (R6). Absent means the demo attest/resolve endpoints stay disabled.
    pub attestor_pk: Option<String>,
    // Filesystem directory for the content-addressed evidence blob store.
    pub evidence_dir: String,
    // Shared secret guarding the privileged demo routes (attest/resolve). Absent means
    // those routes fail closed: without it, no one can trigger settlement.
    pub admin_api_key: Option<String>,
    // When on (and the attestor is enabled), a background worker settles disputes that are
    // due (attested, or past resolveDelay). Off by default so it never surprise-settles.
    pub auto_resolve: bool,
    pub auto_resolve_interval_secs: u64,
    // Sign in with Apple server identifiers and the local private-key path. These are
    // consumed by the account-session endpoint; the private key never reaches clients.
    #[allow(dead_code)]
    pub apple_team_id: Option<String>,
    #[allow(dead_code)]
    pub apple_key_id: Option<String>,
    #[allow(dead_code)]
    pub apple_client_id: Option<String>,
    #[allow(dead_code)]
    pub apple_private_key_path: Option<PathBuf>,
    // Google OAuth client id (the aud of ID tokens from Google Identity Services on web).
    // Absent means the Google sign-in endpoint stays disabled.
    pub google_client_id: Option<String>,
    // Google OAuth iOS client id. iOS Google Sign-In mints ID tokens with the iOS client
    // as aud, so the verifier accepts this in addition to the web client id.
    pub google_ios_client_id: Option<String>,
    // Allowed browser origins for CORS. Empty means permissive (dev/demo fallback); set
    // CORS_ALLOWED_ORIGINS (comma-separated) in production to lock it to the web app.
    pub cors_allowed_origins: Vec<String>,
    // WebAuthn / passkeys. rp_id is the bare domain the iOS app is associated with (its
    // apple-app-site-association webcredentials domain, e.g. recourse.app); rp_origin is
    // https://<rp_id>. Both absent means the passkey endpoints stay disabled.
    pub webauthn_rp_id: Option<String>,
    pub webauthn_rp_origin: Option<String>,
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
}

fn optional_env(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

impl AppConfig {
    pub fn from_env() -> Result<Self> {
        let deployments_path = PathBuf::from(env_or(
            "DEPLOYMENTS_PATH",
            "../deployments/arc-testnet.json",
        ));
        let raw = std::fs::read_to_string(&deployments_path).with_context(|| {
            format!("reading deployment file at {}", deployments_path.display())
        })?;
        let deployment: Deployment =
            serde_json::from_str(&raw).context("parsing deployment JSON")?;

        Ok(Self {
            database_url: env_or(
                "DATABASE_URL",
                "postgres://recourse:recourse@localhost:5433/recourse",
            ),
            rpc_url: env_or("ARC_RPC_URL", "https://arc-testnet.drpc.org"),
            port: env_or("PORT", "8080").parse().context("PORT")?,
            index_interval_secs: env_or("INDEX_INTERVAL_SECS", "15")
                .parse()
                .context("INDEX_INTERVAL_SECS")?,
            demo_mode: env_or("DEMO_MODE", "true") == "true",
            escrow: deployment.escrow,
            policy_registry: deployment.policy_registry,
            chain_id: deployment.chain_id,
            attestor_pk: std::env::var("ATTESTOR_PK")
                .ok()
                .filter(|s| !s.trim().is_empty()),
            evidence_dir: env_or("EVIDENCE_DIR", "./evidence-store"),
            admin_api_key: std::env::var("ADMIN_API_KEY")
                .ok()
                .filter(|s| !s.trim().is_empty()),
            auto_resolve: env_or("ATTESTOR_AUTO_RESOLVE", "false") == "true",
            auto_resolve_interval_secs: env_or("ATTESTOR_AUTO_RESOLVE_INTERVAL_SECS", "30")
                .parse()
                .context("ATTESTOR_AUTO_RESOLVE_INTERVAL_SECS")?,
            apple_team_id: optional_env("APPLE_TEAM_ID"),
            apple_key_id: optional_env("APPLE_KEY_ID"),
            apple_client_id: optional_env("APPLE_CLIENT_ID"),
            apple_private_key_path: optional_env("APPLE_PRIVATE_KEY_PATH").map(PathBuf::from),
            google_client_id: optional_env("GOOGLE_CLIENT_ID"),
            google_ios_client_id: optional_env("GOOGLE_IOS_CLIENT_ID"),
            cors_allowed_origins: optional_env("CORS_ALLOWED_ORIGINS")
                .map(|raw| {
                    raw.split(',')
                        .map(|origin| origin.trim().to_string())
                        .filter(|origin| !origin.is_empty())
                        .collect()
                })
                .unwrap_or_default(),
            webauthn_rp_id: optional_env("WEBAUTHN_RP_ID"),
            webauthn_rp_origin: optional_env("WEBAUTHN_RP_ORIGIN"),
        })
    }
}
