mod attestor;
mod chain;
mod config;
mod db;
mod evidence;
mod indexer;
mod routes;

use actix_cors::Cors;
use actix_web::{web, App, HttpServer};
use anyhow::Result;
use tracing_subscriber::EnvFilter;

#[actix_web::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = config::Config::from_env()?;
    let pool = db::connect(&config.database_url).await?;
    // Drop any projection left over from a different deployment before indexing.
    db::reset_if_deployment_changed(&pool, &format!("{:#x}", config.escrow), config.chain_id as i64).await?;
    let chain = chain::ChainClient::new(&config.rpc_url, config.escrow, config.policy_registry)?;

    // Demo attestor bot (R6): only wired when DEMO_MODE is on and a key is set. It
    // signs delivery attestations and pushes txs; the read API stays usable without it.
    let attestor = if config.demo_mode {
        match &config.attestor_pk {
            Some(pk) => {
                let client = attestor::AttestorClient::new(&config.rpc_url, config.escrow, config.chain_id, pk)?;
                match client.self_check().await {
                    Ok(()) => tracing::info!("attestor bot enabled, signer {} (digest verified)", client.attestor_address()),
                    Err(e) => tracing::warn!("attestor enabled but self-check failed: {e:#}"),
                }
                Some(client)
            }
            None => {
                tracing::info!("attestor bot disabled (ATTESTOR_PK not set)");
                None
            }
        }
    } else {
        None
    };

    // Background indexer keeps Postgres in sync with Arc state.
    {
        let chain = chain.clone();
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        actix_web::rt::spawn(async move {
            indexer::run(chain, pool, interval).await;
        });
    }

    let evidence = evidence::EvidenceStore::new(config.evidence_dir.clone().into())?;

    let port = config.port;
    let chain_id = config.chain_id;
    tracing::info!("recourse-backend listening on :{port} (Arc chain {chain_id})");

    let state = web::Data::new(routes::AppState { pool, config, attestor, evidence });
    // Evidence uploads (photos) exceed the default 256 KB body cap.
    let payload_cfg = web::PayloadConfig::new(10 * 1024 * 1024);
    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .app_data(payload_cfg.clone())
            .wrap(Cors::permissive())
            .configure(routes::configure)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await?;

    Ok(())
}
