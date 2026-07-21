use actix_web::{web, HttpResponse};
use serde_json::json;
use sqlx::PgPool;

use crate::services::AppConfig;

/// GET /health — DB-backed health probe. Reports 503 when Postgres is unreachable, so
/// the endpoint never stays green while the projection is actually down.
pub async fn health_check(pool: web::Data<PgPool>, config: web::Data<AppConfig>) -> HttpResponse {
    match sqlx::query_scalar::<_, i64>("SELECT count(*) FROM payments")
        .fetch_one(pool.get_ref())
        .await
    {
        Ok(indexed) => HttpResponse::Ok().json(json!({
            "status": "ok",
            "chainId": config.chain_id,
            "indexedPayments": indexed,
            "demoMode": config.demo_mode,
        })),
        Err(e) => {
            tracing::error!("health db probe failed: {e}");
            HttpResponse::ServiceUnavailable().json(json!({
                "status": "degraded",
                "error": "database unavailable",
                "chainId": config.chain_id,
            }))
        }
    }
}
