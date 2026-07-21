use crate::config::Config;
use crate::db;
use actix_web::{get, web, HttpResponse, Responder};
use serde::Deserialize;
use serde_json::json;
use sqlx::postgres::PgPool;

pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
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

pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(health)
        .service(list_payments)
        .service(get_payment)
        .service(list_disputes)
        .service(list_policies)
        .service(get_policy);
}
