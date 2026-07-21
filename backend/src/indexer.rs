use crate::chain::ChainClient;
use crate::db;
use sqlx::postgres::PgPool;
use std::time::Duration;
use tracing::{error, info, warn};

// State-polling indexer: reads current onchain state into Postgres each tick. The
// chain stays the source of truth; this is a queryable projection for the read API.
pub async fn run(chain: ChainClient, pool: PgPool, interval_secs: u64) {
    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs));
    loop {
        ticker.tick().await;
        if let Err(e) = index_once(&chain, &pool).await {
            error!("index cycle failed: {e:#}");
        }
    }
}

async fn index_once(chain: &ChainClient, pool: &PgPool) -> anyhow::Result<()> {
    let policy_count = chain.policy_count().await?;
    for id in 1..=policy_count {
        match chain.get_policy(id).await {
            Ok(policy) => db::upsert_policy(pool, &policy).await?,
            Err(e) => warn!("policy {id} read failed: {e:#}"),
        }
    }

    let payment_count = chain.payment_count().await?;
    let mut indexed = 0u64;
    for id in 1..=payment_count {
        let payment = match chain.get_payment(id).await {
            Ok(payment) => payment,
            Err(e) => {
                warn!("payment {id} read failed: {e:#}");
                continue;
            }
        };
        // A verdict only exists once a claim is filed; take it from the onchain
        // previewVerdict (R2), never recomputed here. A transient read failure
        // yields None, and the upsert keeps the last-good verdict (COALESCE) rather
        // than erasing it, so a disputed payment never flickers to no-verdict.
        let verdict = if payment.filed_at != 0 {
            match chain.preview_verdict(id).await {
                Ok(v) => Some(v),
                Err(e) => {
                    warn!("verdict preview for payment {id} failed: {e:#}");
                    None
                }
            }
        } else {
            None
        };
        db::upsert_payment(pool, &payment, verdict.as_ref()).await?;
        indexed += 1;
    }

    info!("indexed {indexed} payments, {policy_count} policies");
    Ok(())
}
