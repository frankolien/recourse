use actix_web::http::header::CONTENT_TYPE;
use actix_web::{web, HttpRequest, HttpResponse};
use serde_json::json;

use crate::services::evidence::EvidenceStore;

/// POST /api/evidence — store an evidence blob, returns its keccak256 hash (the value a
/// buyer pins on-chain as EvidenceItem.hash). Not demo-gated.
pub async fn put_evidence(store: web::Data<EvidenceStore>, req: HttpRequest, body: web::Bytes) -> HttpResponse {
    if body.is_empty() {
        return HttpResponse::BadRequest().json(json!({ "error": "empty body" }));
    }
    let content_type = req
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("application/octet-stream")
        .to_string();
    match store.put(&body, &content_type) {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(e) => {
            tracing::error!("put_evidence: {e:#}");
            HttpResponse::InternalServerError().json(json!({ "error": "store failed" }))
        }
    }
}

/// GET /api/evidence/{hash} — fetch an evidence blob by hash.
pub async fn get_evidence(store: web::Data<EvidenceStore>, path: web::Path<String>) -> HttpResponse {
    match store.get(&path.into_inner()) {
        Ok(Some(blob)) => HttpResponse::Ok().content_type(blob.content_type).body(blob.bytes),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "evidence not found" })),
        Err(e) => HttpResponse::BadRequest().json(json!({ "error": e.to_string() })),
    }
}
