pub mod attestor;
pub mod auth;
pub mod chain;
pub mod evidence;

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
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.to_string())
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
        })
    }
}
