use crate::services::chain::{ChainClient, PaymentState, PolicyState, VerdictState};
use sqlx::postgres::PgPool;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, info, warn};

// The projection mirrors exactly one deployment. If the configured escrow or chain
// differs from what is stored (a redeploy, or a fresh DB), wipe payments and policies
// so stale rows sharing paymentIds with the new deploy never linger, then record the
// active identity. The chain is the source of truth, so a truncate loses nothing.
pub async fn reset_if_deployment_changed(
    pool: &PgPool,
    escrow: &str,
    chain_id: i64,
) -> anyhow::Result<()> {
    let current: Option<(String, i64)> =
        sqlx::query_as("SELECT escrow, chain_id FROM index_meta WHERE id = 1")
            .fetch_optional(pool)
            .await?;
    let changed = current
        .as_ref()
        .is_none_or(|(e, c)| e != escrow || *c != chain_id);
    if changed {
        sqlx::query("TRUNCATE payments, policies")
            .execute(pool)
            .await?;
        sqlx::query(
            r#"
            INSERT INTO index_meta (id, escrow, chain_id) VALUES (1, $1, $2)
            ON CONFLICT (id) DO UPDATE SET escrow = EXCLUDED.escrow, chain_id = EXCLUDED.chain_id
            "#,
        )
        .bind(escrow)
        .bind(chain_id)
        .execute(pool)
        .await?;
    }
    Ok(())
}

// State-polling indexer: reads current onchain state into Postgres each tick. The chain
// stays the source of truth; this is a queryable projection for the read API.
pub async fn run(chain: ChainClient, pool: PgPool, interval_secs: u64) {
    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs));
    loop {
        ticker.tick().await;
        if let Err(e) = index_once(&chain, &pool).await {
            error!("index cycle failed: {e:#}");
        }
    }
}

// Spacing between RPC reads plus bounded retries keep the indexer under public-RPC rate
// limits (HTTP 429 "request limit reached"): a burst of reads every tick trips the limit, so
// space calls out and back off on failure to let the window recover rather than dropping a
// payment for the whole cycle.
const RPC_SPACING: Duration = Duration::from_millis(120);
const RPC_MAX_RETRIES: u32 = 4;

// Retry an idempotent RPC read with exponential backoff. Re-evaluates the call each attempt
// (a future cannot be awaited twice), yielding the first success or the last error. A macro,
// not a fn, so the retried expression can borrow `chain` without async-closure lifetime pain.
macro_rules! rpc_retry {
    ($label:expr, $call:expr) => {{
        let mut attempt = 0u32;
        loop {
            match $call.await {
                Ok(value) => break Ok(value),
                Err(e) => {
                    attempt += 1;
                    if attempt > RPC_MAX_RETRIES {
                        break Err(e);
                    }
                    let backoff = Duration::from_millis(250u64 * 2u64.pow(attempt - 1));
                    warn!(
                        "{} rpc read failed (attempt {}): {}; retry in {:?}",
                        $label, attempt, e, backoff
                    );
                    sleep(backoff).await;
                }
            }
        }
    }};
}

async fn index_once(chain: &ChainClient, pool: &PgPool) -> anyhow::Result<()> {
    let policy_count = rpc_retry!("policy_count", chain.policy_count())?;
    for id in 1..=policy_count {
        match rpc_retry!("get_policy", chain.get_policy(id)) {
            Ok(policy) => upsert_policy(pool, &policy).await?,
            Err(e) => warn!("policy {id} read failed after retries: {e:#}"),
        }
        sleep(RPC_SPACING).await;
    }

    let payment_count = rpc_retry!("payment_count", chain.payment_count())?;
    let mut indexed = 0u64;
    for id in 1..=payment_count {
        let payment = match rpc_retry!("get_payment", chain.get_payment(id)) {
            Ok(payment) => payment,
            Err(e) => {
                warn!("payment {id} read failed after retries: {e:#}");
                continue;
            }
        };
        // A verdict only exists once a claim is filed; take it from the onchain
        // previewVerdict (R2), never recomputed here. A transient read failure yields
        // None, and the upsert keeps the last-good verdict (COALESCE) rather than
        // erasing it, so a disputed payment never flickers to no-verdict.
        let verdict = if payment.filed_at != 0 {
            match rpc_retry!("preview_verdict", chain.preview_verdict(id)) {
                Ok(v) => Some(v),
                Err(e) => {
                    warn!("verdict preview for payment {id} failed after retries: {e:#}");
                    None
                }
            }
        } else {
            None
        };
        upsert_payment(pool, &payment, verdict.as_ref()).await?;
        indexed += 1;
        sleep(RPC_SPACING).await;
    }

    info!("indexed {indexed} payments, {policy_count} policies");

    if let Err(e) = sync_order_refs(chain, pool).await {
        warn!("orderRef sweep failed: {e:#}");
    }
    Ok(())
}

// One getLogs sweep is bounded by chain and provider limits, so scan in chunks.
const LOG_CHUNK_BLOCKS: u64 = 10_000;
// Bound one cycle's sweep so a huge backlog cannot pin the indexer; the next cycles
// continue from wherever the missing set has shrunk to.
const LOG_MAX_CHUNKS_PER_CYCLE: u64 = 400;

// Backfill payments.order_ref from Paid event logs. The escrow's readable state never
// includes orderRef, so the projection learns it from events: find the earliest missing
// payment's paidAt, binary-search the block height near it, then chunk-scan forward.
// Self-quieting: once every payment has an order_ref this does zero RPC work.
async fn sync_order_refs(chain: &ChainClient, pool: &PgPool) -> anyhow::Result<()> {
    let missing: Vec<(i64, i64)> = sqlx::query_as(
        "SELECT payment_id, paid_at FROM payments WHERE order_ref IS NULL ORDER BY paid_at",
    )
    .fetch_all(pool)
    .await?;
    let Some((_, earliest_paid_at)) = missing.first() else {
        return Ok(());
    };
    let mut wanted: std::collections::HashSet<i64> = missing.iter().map(|(id, _)| *id).collect();

    // Start two minutes before the earliest missing payment so clock skew between the
    // block timestamp and paidAt cannot skip the event.
    let target_ts = (*earliest_paid_at as u64).saturating_sub(120);
    let start = rpc_retry!("block_at_or_before", chain.block_at_or_before(target_ts))?;
    let latest = rpc_retry!("block_number", chain.block_number())?;

    let mut from = start;
    let mut chunks = 0u64;
    while from <= latest && !wanted.is_empty() && chunks < LOG_MAX_CHUNKS_PER_CYCLE {
        let to = (from + LOG_CHUNK_BLOCKS - 1).min(latest);
        let events = rpc_retry!("paid_events", chain.paid_events(from, to))?;
        for (payment_id, order_ref) in events {
            let id = payment_id as i64;
            if wanted.remove(&id) {
                sqlx::query("UPDATE payments SET order_ref = $1 WHERE payment_id = $2")
                    .bind(&order_ref)
                    .bind(id)
                    .execute(pool)
                    .await?;
            }
        }
        from = to + 1;
        chunks += 1;
        sleep(RPC_SPACING).await;
    }
    let resolved = missing.len() - wanted.len();
    if resolved > 0 {
        info!(
            "orderRef sweep resolved {resolved} payments ({} still missing)",
            wanted.len()
        );
    }
    Ok(())
}

async fn upsert_payment(
    pool: &PgPool,
    p: &PaymentState,
    v: Option<&VerdictState>,
) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        INSERT INTO payments (
            payment_id, buyer, merchant, beneficiary, policy_id, amount, shares,
            paid_at, filed_at, claim_type, evidence_mask, att_type, att_value,
            evidence_root, verdict_bps, status,
            refund_bps, requires_return, rule_index, matched, verdict_hash, updated_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21, now())
        ON CONFLICT (payment_id) DO UPDATE SET
            buyer = EXCLUDED.buyer,
            merchant = EXCLUDED.merchant,
            beneficiary = EXCLUDED.beneficiary,
            policy_id = EXCLUDED.policy_id,
            amount = EXCLUDED.amount,
            shares = EXCLUDED.shares,
            paid_at = EXCLUDED.paid_at,
            filed_at = EXCLUDED.filed_at,
            claim_type = EXCLUDED.claim_type,
            evidence_mask = EXCLUDED.evidence_mask,
            att_type = EXCLUDED.att_type,
            att_value = EXCLUDED.att_value,
            evidence_root = EXCLUDED.evidence_root,
            verdict_bps = EXCLUDED.verdict_bps,
            status = EXCLUDED.status,
            -- Verdict columns keep their last-good value when the incoming row has none
            -- (a transient previewVerdict read failure), never NULLing a cached verdict.
            -- Verdicts are deterministic and one-way, so old is safe.
            refund_bps = COALESCE(EXCLUDED.refund_bps, payments.refund_bps),
            requires_return = COALESCE(EXCLUDED.requires_return, payments.requires_return),
            rule_index = COALESCE(EXCLUDED.rule_index, payments.rule_index),
            matched = COALESCE(EXCLUDED.matched, payments.matched),
            verdict_hash = COALESCE(EXCLUDED.verdict_hash, payments.verdict_hash),
            updated_at = now()
        "#,
    )
    .bind(p.payment_id)
    .bind(&p.buyer)
    .bind(&p.merchant)
    .bind(&p.beneficiary)
    .bind(p.policy_id)
    .bind(&p.amount)
    .bind(&p.shares)
    .bind(p.paid_at)
    .bind(p.filed_at)
    .bind(p.claim_type)
    .bind(p.evidence_mask)
    .bind(p.att_type)
    .bind(p.att_value)
    .bind(&p.evidence_root)
    .bind(p.verdict_bps)
    .bind(p.status)
    .bind(v.map(|x| x.refund_bps))
    .bind(v.map(|x| x.requires_return))
    .bind(v.map(|x| x.rule_index))
    .bind(v.map(|x| x.matched))
    .bind(v.map(|x| x.verdict_hash.clone()))
    .execute(pool)
    .await?;
    Ok(())
}

async fn upsert_policy(pool: &PgPool, p: &PolicyState) -> anyhow::Result<()> {
    sqlx::query(
        r#"
        INSERT INTO policies (policy_id, merchant, dispute_window, default_refund_bps, policy_hash, rules, updated_at)
        VALUES ($1,$2,$3,$4,$5,$6, now())
        ON CONFLICT (policy_id) DO UPDATE SET
            merchant = EXCLUDED.merchant,
            dispute_window = EXCLUDED.dispute_window,
            default_refund_bps = EXCLUDED.default_refund_bps,
            policy_hash = EXCLUDED.policy_hash,
            rules = EXCLUDED.rules,
            updated_at = now()
        "#,
    )
    .bind(p.policy_id)
    .bind(&p.merchant)
    .bind(p.dispute_window)
    .bind(p.default_refund_bps)
    .bind(&p.policy_hash)
    .bind(&p.rules)
    .execute(pool)
    .await?;
    Ok(())
}
