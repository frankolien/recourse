mod app;
mod handlers;
mod jobs;
mod models;
mod services;

use std::sync::{Arc, Mutex};
use actix_web::HttpServer;
use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;

use crate::services::apple_auth::AppleAuthService;
use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use crate::services::cloudinary::Cloudinary;
use crate::services::evidence::EvidenceStore;
use crate::services::google_auth::GoogleAuthService;
use crate::services::orders::OrderStore;
use crate::services::passkey::PasskeyService;
use crate::services::recovery::{Mailer, RecoveryVault};
use crate::services::safe::SafeClient;
use crate::services::smart_accounts::SmartAccounts;
use crate::services::olien::OlienClient;
use crate::services::treasury::Treasury;
use crate::services::AppConfig;

#[actix_web::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    // Boot-progress logs so a hang before the server binds is visible (e.g. a hosted DB
    // that never answers), instead of the process going silent until the healthcheck fails.
    tracing::info!("recourse-backend booting");
    let config = AppConfig::from_env()?;
    tracing::info!("config loaded; connecting to Postgres");
    // acquire_timeout bounds the initial connection: an unreachable DB errors loudly in a
    // few seconds rather than hanging (on Railway, the private *.railway.internal host can
    // hang; if it does, use the public database URL instead).
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(std::time::Duration::from_secs(10))
        .connect(&config.database_url)
        .await?;
    tracing::info!("Postgres connected; applying migrations");
    sqlx::migrate!("./migrations").run(&pool).await?;
    tracing::info!("migrations applied");
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
    let orders = OrderStore::new(config.orders_dir.clone().into())?;
    let cloudinary = Cloudinary::from_env();
    match &cloudinary {
        Some(_) => tracing::info!("cloudinary image mirror enabled"),
        None => tracing::info!("cloudinary image mirror disabled (CLOUDINARY_URL not set)"),
    }

    let smart_accounts = build_smart_accounts(&config)?;
    let treasury = build_treasury(&config)?;
    match &treasury.push {
        Some(_) => tracing::info!("push alerts enabled (APNs)"),
        None => tracing::warn!("push alerts disabled (set APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8, APNS_BUNDLE_ID)"),
    }
    if let Some(client) = treasury.client.clone() {
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        let relayer = treasury.relayer.clone();
        let push = treasury.push.clone();
        actix_web::rt::spawn(async move {
            jobs::olien_indexer::run(client, pool, interval, relayer, push).await;
        });
    }
    // Money arriving in a consumer account is worth a push too, and needs only the
    // chain client and APNs, so it runs whenever both exist.
    if let (Some(client), Some(push)) = (treasury.client.clone(), treasury.push.clone()) {
        let pool = pool.clone();
        let interval = config.index_interval_secs;
        actix_web::rt::spawn(async move {
            jobs::transfer_alerts::run(client, pool, interval, push).await;
        });
    }

    tracing::info!(
        "recourse-backend listening on :{} (Arc chain {})",
        config.port,
        config.chain_id
    );
    // Bind IPv6 dual-stack (::), not just IPv4 (0.0.0.0): Railway's internal healthcheck
    // reaches the container over IPv6, so an IPv4-only bind fails the healthcheck. On Linux
    // dual-stack, :: also accepts IPv4, so public routing is unaffected.
    let bind = ("::", config.port);
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
            orders.clone(),
            cloudinary.clone(),
            smart_accounts.clone(),
            treasury.clone(),
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

// The treasury service needs the Olien contracts from the deployment file and a funded
// relayer key. Without them the routes answer 503 and the indexer does not start.
fn build_treasury(config: &AppConfig) -> Result<Treasury> {
    let client = match (&config.olien, &config.relayer_pk) {
        (Some(deployment), Some(pk)) => {
            let client = OlienClient::new(&config.rpc_url, pk, deployment.clone(), config.usdc)?;
            tracing::info!(
                "treasury service enabled (factory {:#x}, implementation {:#x}, verifier {:#x}, sub-accounts {:#x}, relayer {:#x})",
                deployment.factory, deployment.implementation, deployment.verifier, deployment.sub_account_implementation, client.relayer()
            );
            Some(client)
        }
        _ => {
            tracing::warn!("treasury service disabled (needs olien in deployments and RELAYER_PK or ATTESTOR_PK)");
            None
        }
    };
    let push = services::push::Push::from_config(config).map(Arc::new);
    Ok(Treasury { client, chain_id: config.chain_id, relayer: Arc::new(Mutex::new(None)), push })
}

// The account routes need three things that are each optional: a funded deployer key
// with the contract addresses, the vault key, and a way to send mail. Each is reported
// at boot so a missing one is a log line now rather than a 500 at enrolment.
fn build_smart_accounts(config: &AppConfig) -> Result<SmartAccounts> {
    let safe = match (&config.attestor_pk, config.p256_owner_factory, &config.safe) {
        (Some(pk), Some(factory), Some(deployment)) => {
            tracing::info!("smart accounts enabled (factory {factory:#x})");
            Some(SafeClient::new(&config.rpc_url, pk, deployment.clone(), factory)?)
        }
        _ => {
            tracing::warn!("smart accounts disabled (needs ATTESTOR_PK, p256OwnerFactory and safe in deployments)");
            None
        }
    };
    let vault = match &config.recovery_vault_key {
        Some(key) => Some(RecoveryVault::from_base64(key).map_err(|message| anyhow::anyhow!(message))?),
        None => {
            tracing::warn!("recovery vault disabled (RECOVERY_VAULT_KEY not set)");
            None
        }
    };
    let mailer = match (&config.resend_api_key, &config.recovery_mail_from, config.recovery_mail_log) {
        (Some(api_key), Some(from), _) => Some(Mailer::Resend {
            client: reqwest::Client::new(),
            api_key: api_key.clone(),
            from: from.clone(),
        }),
        (_, _, true) => {
            tracing::warn!("RECOVERY_MAIL=log: recovery codes will be printed to the log");
            Some(Mailer::Log)
        }
        _ => {
            tracing::warn!("recovery mail disabled (set RESEND_API_KEY and RECOVERY_MAIL_FROM)");
            None
        }
    };
    Ok(SmartAccounts { safe, vault, mailer })
}
