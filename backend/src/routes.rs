use crate::attestor::AttestorClient;
use crate::config::Config;
use crate::db;
use actix_web::{get, post, web, HttpResponse, Responder};
use serde::Deserialize;
use serde_json::json;
use sqlx::postgres::PgPool;

pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
    // Present only in DEMO_MODE with a configured key; drives the demo attest/resolve
    // endpoints. None means those endpoints report disabled.
    pub attestor: Option<AttestorClient>,
}

fn server_error(context: &str, e: anyhow::Error) -> HttpResponse {
    tracing::error!("{context}: {e:#}");
    HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
}

// Health reflects the DB: a probe that reads the payments count. If Postgres is
// unreachable the count query fails and we report 503, so the endpoint never stays
// green while the projection is actually down.
#[get("/health")]
async fn health(state: web::Data<AppState>) -> impl Responder {
    match db::count_payments(&state.pool).await {
        Ok(indexed) => HttpResponse::Ok().json(json!({
            "status": "ok",
            "chainId": state.config.chain_id,
            "indexedPayments": indexed,
            "demoMode": state.config.demo_mode,
        })),
        Err(e) => {
            tracing::error!("health db probe failed: {e:#}");
            HttpResponse::ServiceUnavailable().json(json!({
                "status": "degraded",
                "error": "database unavailable",
                "chainId": state.config.chain_id,
            }))
        }
    }
}

#[derive(Deserialize)]
struct PaymentsQuery {
    merchant: Option<String>,
}

#[get("/api/payments")]
async fn list_payments(state: web::Data<AppState>, q: web::Query<PaymentsQuery>) -> impl Responder {
    match db::list_payments(&state.pool, q.merchant.clone()).await {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => server_error("list_payments", e),
    }
}

#[get("/api/payments/{id}")]
async fn get_payment(state: web::Data<AppState>, path: web::Path<i64>) -> impl Responder {
    match db::get_payment(&state.pool, path.into_inner()).await {
        Ok(Some(row)) => HttpResponse::Ok().json(row),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "payment not found" })),
        Err(e) => server_error("get_payment", e),
    }
}

#[get("/api/disputes")]
async fn list_disputes(state: web::Data<AppState>) -> impl Responder {
    match db::list_disputes(&state.pool).await {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => server_error("list_disputes", e),
    }
}

#[get("/api/policies")]
async fn list_policies(state: web::Data<AppState>) -> impl Responder {
    match db::list_policies(&state.pool).await {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => server_error("list_policies", e),
    }
}

#[get("/api/policies/{id}")]
async fn get_policy(state: web::Data<AppState>, path: web::Path<i64>) -> impl Responder {
    match db::get_policy(&state.pool, path.into_inner()).await {
        Ok(Some(row)) => HttpResponse::Ok().json(row),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "policy not found" })),
        Err(e) => server_error("get_policy", e),
    }
}

// Demo-only endpoints (R6). Gated behind DEMO_MODE via the presence of state.attestor
// (built only when DEMO_MODE is on). The attestor signs objective delivery facts and
// pushes txs; it never decides outcomes (the onchain PolicyEngine computes the verdict).

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AttestBody {
    payment_id: u64,
    // Delivery status: 1 DELIVERED, 2 NOT_DELIVERED.
    value: u8,
}

#[post("/api/demo/attest")]
async fn demo_attest(state: web::Data<AppState>, body: web::Json<AttestBody>) -> impl Responder {
    let Some(attestor) = state.attestor.as_ref() else {
        return HttpResponse::ServiceUnavailable()
            .json(json!({ "error": "attestor disabled; set DEMO_MODE=true and ATTESTOR_PK" }));
    };
    if !(1..=2).contains(&body.value) {
        return HttpResponse::BadRequest()
            .json(json!({ "error": "value must be 1 (DELIVERED) or 2 (NOT_DELIVERED)" }));
    }
    // R8: log every attestor action against the deployment.
    tracing::info!("DEMO attest: payment {} value {}", body.payment_id, body.value);
    match attestor.attest(body.payment_id, body.value).await {
        Ok(out) => HttpResponse::Ok().json(json!({
            "demo": true,
            "paymentId": body.payment_id,
            "value": body.value,
            "attestationTx": out.attestation_tx,
            "digest": out.digest,
        })),
        Err(e) => server_error("demo_attest", e),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ResolveBody {
    payment_id: u64,
}

#[post("/api/demo/resolve")]
async fn demo_resolve(state: web::Data<AppState>, body: web::Json<ResolveBody>) -> impl Responder {
    let Some(attestor) = state.attestor.as_ref() else {
        return HttpResponse::ServiceUnavailable()
            .json(json!({ "error": "attestor disabled; set DEMO_MODE=true and ATTESTOR_PK" }));
    };
    // R8: resolve moves funds; log it explicitly.
    tracing::info!("DEMO resolve (settlement): payment {}", body.payment_id);
    match attestor.resolve(body.payment_id).await {
        Ok(tx) => HttpResponse::Ok().json(json!({
            "demo": true,
            "paymentId": body.payment_id,
            "resolveTx": tx,
        })),
        Err(e) => server_error("demo_resolve", e),
    }
}

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(health)
        .service(list_payments)
        .service(get_payment)
        .service(list_disputes)
        .service(list_policies)
        .service(get_policy)
        .service(demo_attest)
        .service(demo_resolve);
}
