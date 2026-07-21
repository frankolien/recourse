use actix_web::{web, HttpResponse};
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;

use crate::models::PaymentRow;

#[derive(Deserialize)]
pub struct PaymentsQuery {
    pub merchant: Option<String>,
}

/// GET /api/payments — all indexed payments, newest first (optional ?merchant=0x.. filter).
pub async fn list_payments(pool: web::Data<PgPool>, q: web::Query<PaymentsQuery>) -> HttpResponse {
    let result = sqlx::query_as::<_, PaymentRow>(
        "SELECT * FROM payments WHERE ($1::text IS NULL OR merchant = lower($1)) ORDER BY payment_id DESC",
    )
    .bind(q.merchant.clone())
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
