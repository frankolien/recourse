use actix_web::{web, HttpResponse};
use serde_json::json;
use sqlx::PgPool;

use crate::models::PaymentRow;

/// GET /api/disputes — payments with a filed claim, newest first.
pub async fn list_disputes(pool: web::Data<PgPool>) -> HttpResponse {
    let result = sqlx::query_as::<_, PaymentRow>(
        "SELECT * FROM payments WHERE filed_at <> 0 ORDER BY filed_at DESC",
    )
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
