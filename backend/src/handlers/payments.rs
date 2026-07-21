use actix_web::{web, HttpResponse};
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;

use crate::models::PaymentRow;

#[derive(Deserialize)]
pub struct PaymentsQuery {
    pub merchant: Option<String>,
    pub buyer: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// Page bounds: a sane default, a hard cap so one request cannot pull the whole table.
const DEFAULT_LIMIT: i64 = 100;
const MAX_LIMIT: i64 = 500;

fn page(limit: Option<i64>, offset: Option<i64>) -> (i64, i64) {
    (
        limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT),
        offset.unwrap_or(0).max(0),
    )
}

/// GET /api/payments — indexed payments, newest first. Filters: ?merchant=0x.. and/or
/// ?buyer=0x.. (the mobile app scopes to its buyer). Paginated with ?limit= and ?offset=.
pub async fn list_payments(pool: web::Data<PgPool>, q: web::Query<PaymentsQuery>) -> HttpResponse {
    let (limit, offset) = page(q.limit, q.offset);
    let result = sqlx::query_as::<_, PaymentRow>(
        "SELECT * FROM payments \
         WHERE ($1::text IS NULL OR merchant = lower($1)) \
           AND ($2::text IS NULL OR buyer = lower($2)) \
         ORDER BY payment_id DESC LIMIT $3 OFFSET $4",
    )
    .bind(q.merchant.clone())
    .bind(q.buyer.clone())
    .bind(limit)
    .bind(offset)
    .fetch_all(pool.get_ref())
    .await;
    match result {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => {
            tracing::error!("list_payments: {e}");
            HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
        }
    }
}

/// GET /api/payments/{id} — one payment with its verdict.
pub async fn get_payment(pool: web::Data<PgPool>, path: web::Path<i64>) -> HttpResponse {
    let result = sqlx::query_as::<_, PaymentRow>("SELECT * FROM payments WHERE payment_id = $1")
        .bind(path.into_inner())
        .fetch_optional(pool.get_ref())
        .await;
    match result {
        Ok(Some(row)) => HttpResponse::Ok().json(row),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "payment not found" })),
        Err(e) => {
            tracing::error!("get_payment: {e}");
            HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
        }
    }
}
