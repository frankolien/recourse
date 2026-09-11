// Watches for dollars landing on a deposit address and sends them to Arc.
//
// A person is given an address on Base and sends USDC to it from wherever they keep
// money. Nothing happens on chain until somebody pays for a transaction, so this does.
// It never holds the money: the vault at that address can only burn into a CCTP message
// addressed to the one Arc account it was built for, and Circle mints the other side.
//
// The cursor starts at the chain head, so a first run does not try to sweep history.

use alloy::primitives::Address;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};

use crate::services::deposits::DepositClient;

// Deposits are rare next to the chain's traffic, so a wide window catches up quickly
// after a restart while staying inside the log limits public endpoints impose.
const CHUNK_BLOCKS: u64 = 2_000;
const ADDRESSES_PER_QUERY: usize = 500;

pub async fn run(client: Arc<DepositClient>, pool: PgPool, interval_secs: u64) {
    // An address nothing can sweep is worse than no address at all, so the job refuses
    // to start rather than running against a chain with no factory on it.
    if !client.ready().await {
        warn!(
            "deposit sweeper idle: no factory at {:#x} on {}",
            client.factory, client.chain.name
        );
        return;
    }
    info!(
        "deposit sweeper watching {} for {:#x}, paying from {:#x}",
        client.chain.name,
        client.factory,
        client.relayer()
    );
    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs.max(5)));
    loop {
        ticker.tick().await;
        if let Err(e) = cycle(&client, &pool).await {
            warn!("deposit sweep failed: {e:#}");
        }
    }
}

async fn cycle(client: &DepositClient, pool: &PgPool) -> anyhow::Result<()> {
    let head = client.block_number().await?;
    let chain = client.chain.chain_id as i64;

    let cursor: Option<(i64,)> = sqlx::query_as("SELECT block FROM deposit_sweep_cursor WHERE chain_id = $1")
        .bind(chain)
        .fetch_optional(pool)
        .await?;
    let from = match cursor {
        Some((block,)) => block as u64 + 1,
        None => {
            save_cursor(pool, chain, head).await?;
            return Ok(());
        }
    };
    if from > head {
        return Ok(());
    }
    let to = head.min(from + CHUNK_BLOCKS - 1);

    // The deposit address is a function of the Arc account and of the factory's own
    // code, so only addresses this factory issued are watched. One from a previous
    // factory is not an address this build can collect from, and watching it would
    // mean seeing the money land and then sweeping a different, empty vault.
    let rows: Vec<(String, String)> = sqlx::query_as(
        "SELECT sa.safe_address, d.address FROM deposit_addresses d JOIN smart_accounts sa ON sa.account_id = d.account_id \
         WHERE d.chain_id = $1 AND d.factory = $2 AND sa.status = 'live'",
    )
    .bind(chain)
    .bind(format!("{:#x}", client.factory))
    .fetch_all(pool)
    .await?;
    let mut owner_of: HashMap<Address, Address> = HashMap::new();
    for (safe, deposit) in rows {
        if let (Ok(safe), Ok(deposit)) = (safe.parse::<Address>(), deposit.parse::<Address>()) {
            owner_of.insert(deposit, safe);
        }
    }
    if owner_of.is_empty() {
        save_cursor(pool, chain, to).await?;
        return Ok(());
    }

    let watched: Vec<Address> = owner_of.keys().copied().collect();
    for batch in watched.chunks(ADDRESSES_PER_QUERY) {
        if !client.usdc_received(batch, from, to).await?.is_empty() {
            info!("deposit sweep: dollars landed on {} in blocks {from}..{to}", client.chain.name);
            break;
        }
    }
    // The cursor moves whether or not the sweep worked, so what gets swept is decided
    // by what the vaults actually hold rather than by which logs this window happened
    // to contain. A sweep that failed is retried next cycle instead of being lost with
    // the window it was noticed in.
    let holding = client.funded(&watched).await?;
    let arrived: Vec<Address> = holding.iter().filter_map(|d| owner_of.get(d).copied()).collect();

    if !arrived.is_empty() {
        info!(
            "deposit sweep: {} vault(s) holding on {}",
            arrived.len(),
            client.chain.name
        );
        match client.collect(&arrived).await {
            Ok(hashes) => {
                for hash in hashes {
                    info!("deposit sweep sent {hash:#x}");
                }
                // collectBatch catches a failing collect and returns normally, so a
                // receipt says nothing about whether the money moved. The balances do.
                match client.funded(&holding).await {
                    Ok(still) if !still.is_empty() => warn!(
                        "deposit sweep: {} vault(s) on {} still hold their dollars after sweeping",
                        still.len(),
                        client.chain.name
                    ),
                    Ok(_) => {}
                    Err(e) => warn!("deposit sweep could not re-read balances: {e:#}"),
                }
            }
            // The money is safe in the vault either way and the balance check above
            // finds it again next cycle.
            Err(e) => warn!("deposit sweep could not send: {e:#}"),
        }
    }

    save_cursor(pool, chain, to).await
}

async fn save_cursor(pool: &PgPool, chain_id: i64, block: u64) -> anyhow::Result<()> {
    sqlx::query(
        "INSERT INTO deposit_sweep_cursor (chain_id, block) VALUES ($1, $2)
         ON CONFLICT (chain_id) DO UPDATE SET block = EXCLUDED.block, updated_at = now()",
    )
    .bind(chain_id)
    .bind(block as i64)
    .execute(pool)
    .await?;
    Ok(())
}
