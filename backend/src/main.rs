mod app;
mod handlers;
mod jobs;
mod models;
mod services;

use actix_web::HttpServer;
use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

use crate::services::apple_auth::AppleAuthService;
use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use crate::services::evidence::EvidenceStore;
use crate::services::google_auth::GoogleAuthService;
use crate::services::passkey::PasskeyService;
use crate::services::AppConfig;

#[actix_web::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let config = AppConfig::from_env()?;
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&config.database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    // Drop any projection left over from a different deployment before indexing.
    jobs::indexer::reset_if_deployment_changed(
        &pool,
        &format!("{:#x}", config.escrow),
        config.chain_id as i64,
    )
    .await?;

    let chain = ChainClient::new(&config.rpc_url, config.escrow, config.policy_registry)?;
    let attestor = build_attestor(&config).await?;
    let apple_auth = AppleAuthService::from_config(&config)?;
    let google_auth = GoogleAuthService::from_config(&config)?;
    let passkey = PasskeyService::from_config(&config)?;

    // Background indexer keeps Postgres in sync with Arc state.
    {
        let chain = chain.clone();
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        actix_web::rt::spawn(async move {
            jobs::indexer::run(chain, pool, interval).await;
        });
    }

    // Automated settlement: hands-off resolution of disputes that are due. Needs the
    // attestor's funded wallet to send resolve txs, and is opt-in (ATTESTOR_AUTO_RESOLVE).
    if config.auto_resolve {
        match (&attestor, chain.resolve_delay().await) {
            (Some(attestor), Ok(resolve_delay)) => {
                let attestor = attestor.clone();
                let chain = chain.clone();
                let pool = pool.clone();
                let interval = config.auto_resolve_interval_secs;
                actix_web::rt::spawn(async move {
                    jobs::resolver::run(attestor, chain, pool, interval, resolve_delay).await;
                });
            }
            (None, _) => tracing::warn!(
                "ATTESTOR_AUTO_RESOLVE set but attestor is disabled; not starting the resolver"
            ),
            (_, Err(e)) => {
                tracing::warn!("auto-resolver not started: reading resolveDelay failed: {e:#}")
            }
        }
    }

    let evidence = EvidenceStore::new(config.evidence_dir.clone().into())?;

    tracing::info!(
        "recourse-backend listening on :{} (Arc chain {})",
        config.port,
        config.chain_id
    );
    let bind = ("0.0.0.0", config.port);
    HttpServer::new(move || {
        app::build_app(
            pool.clone(),
            config.clone(),
            chain.clone(),
            attestor.clone(),
            apple_auth.clone(),
            google_auth.clone(),
            passkey.clone(),
            evidence.clone(),
        )
    })
    .bind(bind)?
    .run()
    .await?;

    Ok(())
}

// Demo attestor (R6): only wired when DEMO_MODE is on and a key is set. A boot self-check
// confirms the local EIP-712 digest matches the escrow, warning (not crashing) on drift
// so the read API stays usable.
async fn build_attestor(config: &AppConfig) -> Result<Option<AttestorClient>> {
    if !config.demo_mode {
        return Ok(None);
    }
    let Some(pk) = &config.attestor_pk else {
        tracing::info!("attestor bot disabled (ATTESTOR_PK not set)");
        return Ok(None);
    };
    let client = AttestorClient::new(&config.rpc_url, config.escrow, config.chain_id, pk)?;
    // Fail closed: a failed self-check means our EIP-712 digest disagrees with the escrow,
    // so any signature we produce would be rejected onchain. Disable the attestor rather
    // than expose a writer that only ever submits invalid attestations.
    match client.self_check().await {
        Ok(()) => {
            tracing::info!(
                "attestor bot enabled, signer {} (digest verified)",
                client.attestor_address()
            );
            Ok(Some(client))
        }
        Err(e) => {
            tracing::warn!("attestor disabled: self-check failed: {e:#}");
            Ok(None)
        }
    }
}
