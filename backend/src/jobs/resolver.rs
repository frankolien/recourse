use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use sqlx::PgPool;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tracing::{info, warn};

// RecourseEscrow.Status::Disputed. Only disputed payments can be resolved.
const STATUS_DISPUTED: i32 = 2;

// Mirrors the escrow's resolve() precondition exactly (RecourseEscrow.sol):
//   status == Disputed && (attType != 0 || now >= filedAt + resolveDelay)
// Attested disputes settle immediately; un-attested ones only after resolveDelay, when the
// policy default applies. This never decides the verdict (R2/R4): resolve() runs the
// onchain PolicyEngine. The worker only picks the moment a settlement is already due.
pub fn is_resolvable(
    status: i32,
    att_type: i32,
    filed_at: i64,
    resolve_delay: i64,
    now: i64,
) -> bool {
    status == STATUS_DISPUTED && (att_type != 0 || now >= filed_at + resolve_delay)
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

// Automated settlement service: on each tick, find disputed payments that are due and
// resolve them. Discretion-free (the contract computes the verdict); this only converts
// the manual resolve step into a hands-off internal service. Every settlement is logged
// (R8). Off unless ATTESTOR_AUTO_RESOLVE is set, so it never surprise-settles a rehearsal.
pub async fn run(
    attestor: AttestorClient,
    chain: ChainClient,
    pool: PgPool,
    interval_secs: u64,
    resolve_delay: u64,
) {
    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs.max(5)));
    info!(
        "auto-resolver enabled: settling due disputes every {}s (resolveDelay {}s)",
        interval_secs.max(5),
        resolve_delay
    );
    loop {
        ticker.tick().await;
        if let Err(e) = tick(&attestor, &chain, &pool, resolve_delay as i64).await {
            warn!("auto-resolver tick failed: {e:#}");
        }
    }
}

async fn tick(
    attestor: &AttestorClient,
    chain: &ChainClient,
    pool: &PgPool,
    resolve_delay: i64,
) -> anyhow::Result<()> {
    // The projection is a cheap first filter; readiness is confirmed against the live chain
    // per candidate so a stale row cannot cause a double-settle (a settled payment reads as
    // status != Disputed and is skipped).
    let candidates: Vec<(i64,)> =
        sqlx::query_as("SELECT payment_id FROM payments WHERE status = $1 ORDER BY payment_id")
            .bind(STATUS_DISPUTED)
            .fetch_all(pool)
            .await?;
    let now = now_secs();
    for (payment_id,) in candidates {
        let p = match chain.get_payment(payment_id as u64).await {
            Ok(p) => p,
            Err(e) => {
                warn!("auto-resolver: reading payment {payment_id} failed: {e:#}");
                continue;
            }
        };
        if !is_resolvable(p.status, p.att_type, p.filed_at, resolve_delay, now) {
            continue;
        }
        let reason = if p.att_type != 0 {
            "attested"
        } else {
            "resolveDelay elapsed"
        };
        info!("auto-resolver: settling disputed payment {payment_id} ({reason})");
        match attestor.resolve(payment_id as u64).await {
            Ok(tx) => info!("auto-resolver: settled payment {payment_id} in {tx}"),
            Err(e) => warn!("auto-resolver: resolving payment {payment_id} failed: {e:#}"),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn readiness_matches_contract_precondition() {
        let delay = 60;
        // Not disputed: never resolvable, whatever the timing.
        assert!(!is_resolvable(1, 0, 1000, delay, 5000)); // Paid
        assert!(!is_resolvable(3, 1, 1000, delay, 5000)); // Settled
                                                          // Disputed and attested (attType != 0): resolvable immediately.
        assert!(is_resolvable(2, 1, 1000, delay, 1000));
        // Disputed, un-attested, before the delay: not yet.
        assert!(!is_resolvable(2, 0, 1000, delay, 1000 + delay - 1));
        // Disputed, un-attested, at/after the delay: resolvable (default applies).
        assert!(is_resolvable(2, 0, 1000, delay, 1000 + delay));
        assert!(is_resolvable(2, 0, 1000, delay, 9999));
    }
}
