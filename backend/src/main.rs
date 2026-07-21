mod chain;
mod config;
mod db;
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
    let chain = chain::ChainClient::new(&config.rpc_url, config.escrow, config.policy_registry)?;

    // Background indexer keeps Postgres in sync with Arc state.
    {
        let chain = chain.clone();
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        actix_web::rt::spawn(async move {
            indexer::run(chain, pool, interval).await;
        });
    }

    let port = config.port;
    let chain_id = config.chain_id;
    tracing::info!("recourse-backend listening on :{port} (Arc chain {chain_id})");

    let state = web::Data::new(routes::AppState { pool, config });
    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .wrap(Cors::permissive())
            .configure(routes::configure)
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await?;

    Ok(())
}
