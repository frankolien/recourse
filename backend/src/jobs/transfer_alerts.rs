// Tells a phone when money lands in its account. USDC Transfer events into every
// live Safe are read in one query per cycle; each one becomes an alert naming the
// sender by @handle, by treasury name, or by short address. The cursor starts at
// the chain head, so the first run tells nobody about the past.

use alloy::primitives::{Address, U256};
use alloy::sol_types::SolEvent;
use serde_json::json;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};

use crate::services::olien::{OlienClient, IERC20};
use crate::services::push::Push;

// drpc caps a getLogs answer at 10k entries; deposits are rare, so a wide window
// catches up fast after a restart without tripping the cap.
const CHUNK_BLOCKS: u64 = 2_000;
const ADDRESSES_PER_QUERY: usize = 200;

pub async fn run(client: OlienClient, pool: PgPool, interval_secs: u64, push: Arc<Push>) {
    let mut ticker = tokio::time::interval(Duration::from_secs(interval_secs.max(5)));
    loop {
        ticker.tick().await;
        if let Err(e) = cycle(&client, &pool, &push).await {
            warn!("received-money watch failed: {e:#}");
        }
    }
}

struct Recipient {
    account_id: i64,
    cloud_owner: String,
}

async fn cycle(client: &OlienClient, pool: &PgPool, push: &Push) -> anyhow::Result<()> {
    let head = client.block_number().await?;
    let cursor: Option<(i64,)> = sqlx::query_as("SELECT block FROM transfer_alert_cursor WHERE id = 1").fetch_optional(pool).await?;
    let from = match cursor {
        Some((block,)) => block as u64 + 1,
        None => {
            save_cursor(pool, head).await?;
            return Ok(());
        }
    };
    if from > head {
        return Ok(());
    }
    let to = head.min(from + CHUNK_BLOCKS - 1);

    let rows: Vec<(i64, String, String)> = sqlx::query_as("SELECT account_id, safe_address, cloud_owner FROM smart_accounts WHERE status = 'live'").fetch_all(pool).await?;
    let mut recipients: HashMap<Address, Recipient> = HashMap::new();
    for (account_id, safe, cloud_owner) in rows {
        if let Ok(address) = safe.parse::<Address>() {
            recipients.insert(address, Recipient { account_id, cloud_owner: cloud_owner.to_lowercase() });
        }
    }
    if recipients.is_empty() {
        save_cursor(pool, to).await?;
        return Ok(());
    }

    let addresses: Vec<Address> = recipients.keys().copied().collect();
    for batch in addresses.chunks(ADDRESSES_PER_QUERY) {
        let logs = client.usdc_received(batch, from, to).await?;
        for log in logs {
            let Ok(event) = IERC20::Transfer::decode_log(&log.inner) else { continue };
            let Some(recipient) = recipients.get(&event.to) else { continue };
            // The account's own Cloud Key moving an older balance into the Safe is not
            // money arriving; the phone did that itself.
            if format!("{:#x}", event.from) == recipient.cloud_owner {
                continue;
            }
            let sender = sender_name(pool, event.from).await;
            let amount = dollars(event.value);
            let tx = log.transaction_hash.map(|h| format!("{h:#x}")).unwrap_or_default();
            info!("received-money: account {} got {amount} from {sender} ({tx})", recipient.account_id);
            push.notify(
                pool,
                &[recipient.account_id],
                &format!("Received ${amount}"),
                &format!("From {sender}"),
                json!({ "kind": "transfer", "txHash": tx }),
            )
            .await;
        }
    }
    save_cursor(pool, to).await
}

async fn save_cursor(pool: &PgPool, block: u64) -> anyhow::Result<()> {
    sqlx::query("INSERT INTO transfer_alert_cursor (id, block) VALUES (1, $1) ON CONFLICT (id) DO UPDATE SET block = EXCLUDED.block, updated_at = now()")
        .bind(block as i64)
        .execute(pool)
        .await?;
    Ok(())
}

/// A Recourse account by @handle, an Olien by its name, anyone else by short address.
async fn sender_name(pool: &PgPool, from: Address) -> String {
    let lower = format!("{from:#x}");
    let handle: Option<(String,)> = sqlx::query_as(
        "SELECT h.handle FROM account_handles h
           LEFT JOIN smart_accounts sa ON sa.account_id = h.account_id
          WHERE lower(h.wallet_address) = $1 OR lower(sa.safe_address) = $1
          LIMIT 1",
    )
    .bind(&lower)
    .fetch_optional(pool)
    .await
    .unwrap_or(None);
    if let Some((handle,)) = handle {
        return format!("@{handle}");
    }
    let olien: Option<(String,)> = sqlx::query_as("SELECT name FROM olien_accounts WHERE lower(address) = $1 LIMIT 1")
        .bind(&lower)
        .fetch_optional(pool)
        .await
        .unwrap_or(None);
    if let Some((name,)) = olien {
        return name;
    }
    let text = format!("{from:#x}");
    format!("{}...{}", &text[..6], &text[text.len() - 4..])
}

/// USDC has six decimals; the alert shows cents, and drops them when they are zero.
fn dollars(value: U256) -> String {
    let units: u128 = value.try_into().unwrap_or(u128::MAX);
    let whole = units / 1_000_000;
    let cents = (units % 1_000_000) / 10_000;
    let whole_text = whole
        .to_string()
        .as_bytes()
        .rchunks(3)
        .rev()
        .map(|chunk| std::str::from_utf8(chunk).unwrap_or(""))
        .collect::<Vec<_>>()
        .join(",");
    if cents == 0 {
        whole_text
    } else {
        format!("{whole_text}.{cents:02}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dollars_read_like_money() {
        assert_eq!(dollars(U256::from(10_000_000u64)), "10");
        assert_eq!(dollars(U256::from(16_500_250_000u64)), "16,500.25");
        assert_eq!(dollars(U256::from(5_000u64)), "0");
    }
}
