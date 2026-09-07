// Where to send dollars from another chain.
//
// The answer is a contract address on Base whose only power is paying this account on
// Arc. It is asked of the factory rather than computed here, because a person is about
// to send money to whatever this returns and the chain is the only authority worth
// trusting for it. Cached afterwards, since the answer never changes.

use actix_web::{web, HttpRequest, HttpResponse};
use alloy::primitives::Address;
use serde::Serialize;
use sqlx::PgPool;
use std::sync::Arc;

use crate::handlers::auth::{account_error_response, bearer_token, error_response};
use crate::services::account_sessions;
use crate::services::deposits::DepositClient;

#[derive(Serialize)]
pub struct DepositAddress {
    pub chain: String,
    pub chain_name: String,
    pub chain_id: u64,
    pub address: String,
    /// Below this a deposit costs more to move than it is worth, so the contract makes
    /// it wait for company rather than burning it.
    pub minimum: String,
    pub token: String,
}

/// GET /api/me/deposit-address - the address to show, per chain we accept.
pub async fn address(
    pool: web::Data<PgPool>,
    client: web::Data<Option<Arc<DepositClient>>>,
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
    let Some(client) = client.get_ref().clone() else {
        return HttpResponse::Ok().json(Vec::<DepositAddress>::new());
    };

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

    let chain_id = client.chain.chain_id as i64;
    let cached: Option<(String,)> =
        sqlx::query_as("SELECT address FROM deposit_addresses WHERE account_id = $1 AND chain_id = $2")
            .bind(profile.account_id)
            .bind(chain_id)
            .fetch_optional(pool.get_ref())
            .await
            .unwrap_or(None);

    let address = match cached {
        Some((address,)) => address,
        None => match client.address_for(safe).await {
            Ok(address) => {
                let text = format!("{address:#x}");
                // Cached so the sweeper has a list to watch without asking the chain
                // about every account on every cycle.
                let _ = sqlx::query(
                    "INSERT INTO deposit_addresses (account_id, chain_id, address) VALUES ($1, $2, $3)
                     ON CONFLICT (account_id, chain_id) DO UPDATE SET address = EXCLUDED.address",
                )
                .bind(profile.account_id)
                .bind(chain_id)
                .bind(&text)
                .execute(pool.get_ref())
                .await;
                text
            }
            Err(e) => return error_response(503, &format!("could not reach the deposit factory: {e}")),
        },
    };

    HttpResponse::Ok().json(vec![DepositAddress {
        chain: client.chain.key.clone(),
        chain_name: client.chain.name.clone(),
        chain_id: client.chain.chain_id,
        address,
        minimum: "1".into(),
        token: format!("{:#x}", client.chain.usdc),
    }])
}
