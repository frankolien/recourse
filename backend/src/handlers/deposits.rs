// Where to send dollars from another chain.
//
// One address, good on every chain we sweep. That is not a convenience: the vault's
// creation code is identical everywhere and the factory sits at one address on every
// chain, so the same person resolves to the same deposit address wherever they send
// from. The answer is asked of each chain rather than computed here, because a person
// is about to send money to whatever this returns and the chain is the only authority
// worth trusting for it. A chain that has no factory yet is left out rather than
// advertised, and the answers are compared against each other before any of them is
// shown. Cached afterwards, since the answer never changes.

use actix_web::{web, HttpRequest, HttpResponse};
use alloy::primitives::Address;
use serde::Serialize;
use sqlx::PgPool;
use std::sync::Arc;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::account_sessions;
use crate::services::deposits::DepositClient;

#[derive(Serialize)]
pub struct DepositChainInfo {
    pub chain: String,
    pub chain_name: String,
    pub chain_id: u64,
    pub token: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DepositAddress {
    /// The same on every chain listed below.
    pub address: String,
    /// Below this a deposit costs more to move than it is worth, so the contract makes
    /// it wait for company rather than burning it.
    pub minimum: String,
    pub chains: Vec<DepositChainInfo>,
}

/// GET /api/me/deposit-address - one address, and the chains it is good on.
pub async fn address(
    pool: web::Data<PgPool>,
    clients: web::Data<Vec<Arc<DepositClient>>>,
    req: HttpRequest,
) -> HttpResponse {
    let token = match bearer_token(&req) {
        Ok(token) => token,
        Err((status, message)) => return error_response(status, &message),
    };
    let profile = match account_sessions::account_for_access_token(pool.get_ref(), token).await {
        Ok(profile) => profile,
        Err(error) => return account_error_response("reading account session", error),
    };

    // No factory configured means the door is shut. Saying so plainly beats handing out
    // an address that nothing will ever sweep.
    if clients.get_ref().is_empty() {
        return HttpResponse::Ok().json(DepositAddress { address: String::new(), minimum: "1".into(), chains: Vec::new() });
    }

    let safe: Option<(String,)> =
        match sqlx::query_as("SELECT safe_address FROM smart_accounts WHERE account_id = $1 AND status = 'live'")
            .bind(profile.account_id)
            .fetch_optional(pool.get_ref())
            .await
        {
            Ok(row) => row,
            Err(e) => return error_response(500, &format!("reading the account: {e}")),
        };
    let Some((safe,)) = safe else {
        return error_response(409, "this account has no wallet yet");
    };
    let Ok(safe) = safe.parse::<Address>() else {
        return error_response(500, "the account's address is not readable");
    };

    let mut answer: Option<String> = None;
    let mut chains = Vec::new();
    for client in clients.get_ref() {
        let chain_id = client.chain.chain_id as i64;
        // Scoped to the factory, because the address is a function of the factory's
        // code as well as the account: a widened chain list changes the factory's
        // address, and every address the previous one issued is one this build cannot
        // sweep. A swap must miss the cache rather than be served from it.
        let factory = format!("{:#x}", client.factory);
        let cached: Option<(String,)> = sqlx::query_as(
            "SELECT address FROM deposit_addresses WHERE account_id = $1 AND chain_id = $2 AND factory = $3",
        )
        .bind(profile.account_id)
        .bind(chain_id)
        .bind(&factory)
        .fetch_optional(pool.get_ref())
        .await
        .unwrap_or(None);

        let address = match cached {
            Some((address,)) => address,
            // A chain with no factory on it cannot answer, and is quietly left out.
            // The dollars would still be safe if sent there, but we do not invite it.
            None => match client.address_for(safe).await {
                Ok(address) => {
                    let text = format!("{address:#x}");
                    // Cached so the sweeper has a list to watch without asking the chain
                    // about every account on every cycle.
                    let _ = sqlx::query(
                        "INSERT INTO deposit_addresses (account_id, chain_id, address, factory) VALUES ($1, $2, $3, $4)
                         ON CONFLICT (account_id, chain_id) DO UPDATE SET address = EXCLUDED.address, factory = EXCLUDED.factory",
                    )
                    .bind(profile.account_id)
                    .bind(chain_id)
                    .bind(&text)
                    .bind(&factory)
                    .execute(pool.get_ref())
                    .await;
                    text
                }
                Err(_) => continue,
            },
        };

        // Every chain must name the same address. If one disagrees the deployment is
        // wrong, and showing any of them would be showing a guess.
        match &answer {
            None => answer = Some(address),
            Some(first) if first != &address => {
                return error_response(500, "deposit addresses disagree between chains");
            }
            Some(_) => {}
        }
        chains.push(DepositChainInfo {
            chain: client.chain.key.clone(),
            chain_name: client.chain.name.clone(),
            chain_id: client.chain.chain_id,
            token: format!("{:#x}", client.chain.usdc),
        });
    }

    let Some(address) = answer else {
        return error_response(503, "could not reach the deposit factory on any chain");
    };
    HttpResponse::Ok().json(DepositAddress { address, minimum: "1".into(), chains })
}
