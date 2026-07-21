use actix_web::{web, HttpResponse};
use serde_json::json;
use sqlx::PgPool;

use crate::models::PolicyRow;

/// GET /api/policies — all indexed policies, newest first.
pub async fn list_policies(pool: web::Data<PgPool>) -> HttpResponse {
    let result = sqlx::query_as::<_, PolicyRow>("SELECT * FROM policies ORDER BY policy_id DESC")
        .fetch_all(pool.get_ref())
        .await;
    match result {
        Ok(rows) => HttpResponse::Ok().json(rows),
        Err(e) => {
            tracing::error!("list_policies: {e}");
            HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
        }
    }
}

/// GET /api/policies/{id} — one policy with its rules and hash.
pub async fn get_policy(pool: web::Data<PgPool>, path: web::Path<i64>) -> HttpResponse {
    let result = sqlx::query_as::<_, PolicyRow>("SELECT * FROM policies WHERE policy_id = $1")
        .bind(path.into_inner())
        .fetch_optional(pool.get_ref())
        .await;
    match result {
        Ok(Some(row)) => HttpResponse::Ok().json(row),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "policy not found" })),
        Err(e) => {
            tracing::error!("get_policy: {e}");
            HttpResponse::InternalServerError().json(json!({ "error": "query failed" }))
        }
    }
}
