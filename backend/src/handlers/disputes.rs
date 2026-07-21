use actix_web::{web, HttpResponse};
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;

use crate::models::PaymentRow;

#[derive(Deserialize)]
pub struct DisputesQuery {
    pub buyer: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// GET /api/disputes — payments with a filed claim, newest first. Optional ?buyer=0x..
/// filter (the mobile app scopes to its buyer) and ?limit=/?offset= pagination.
pub async fn list_disputes(pool: web::Data<PgPool>, q: web::Query<DisputesQuery>) -> HttpResponse {
    let limit = q.limit.unwrap_or(100).clamp(1, 500);
    let offset = q.offset.unwrap_or(0).max(0);
    let result = sqlx::query_as::<_, PaymentRow>(
        "SELECT * FROM payments \
         WHERE filed_at <> 0 AND ($1::text IS NULL OR buyer = lower($1)) \
         ORDER BY filed_at DESC LIMIT $2 OFFSET $3",
    )
    .bind(q.buyer.clone())
    .bind(limit)
    .bind(offset)
    .fetch_all(pool.get_ref())
    .await;
    match result {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => {
            tracing::error!("list_disputes: {e}");
            HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
        }
    }
}
