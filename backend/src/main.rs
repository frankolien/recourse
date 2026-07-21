mod app;
mod handlers;
mod jobs;
mod models;
mod services;

use actix_web::HttpServer;
use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use crate::services::evidence::EvidenceStore;
use crate::services::AppConfig;

#[actix_web::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = AppConfig::from_env()?;
    let pool = PgPoolOptions::new().max_connections(5).connect(&config.database_url).await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    // Drop any projection left over from a different deployment before indexing.
    jobs::indexer::reset_if_deployment_changed(&pool, &format!("{:#x}", config.escrow), config.chain_id as i64)
        .await?;

    let chain = ChainClient::new(&config.rpc_url, config.escrow, config.policy_registry)?;
    let attestor = build_attestor(&config).await?;

    // Background indexer keeps Postgres in sync with Arc state.
    {
        let chain = chain.clone();
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        actix_web::rt::spawn(async move {
            jobs::indexer::run(chain, pool, interval).await;
        });
    }

    let evidence = EvidenceStore::new(config.evidence_dir.clone().into())?;

    tracing::info!("recourse-backend listening on :{} (Arc chain {})", config.port, config.chain_id);
    let bind = ("0.0.0.0", config.port);
    HttpServer::new(move || app::build_app(pool.clone(), config.clone(), attestor.clone(), evidence.clone()))
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
    match client.self_check().await {
        Ok(()) => tracing::info!("attestor bot enabled, signer {} (digest verified)", client.attestor_address()),
        Err(e) => tracing::warn!("attestor enabled but self-check failed: {e:#}"),
    }
    Ok(Some(client))
}
