use actix_web::http::header::CONTENT_TYPE;
use actix_web::{web, HttpRequest, HttpResponse};
use serde_json::json;

use crate::services::orders::{parse_manifest, OrderStore};
use crate::services::AppConfig;

// Product images the buyer will render in checkout. Anything else is refused so the
// store cannot be used as a general file host.
const IMAGE_TYPES: [&str; 4] = ["image/jpeg", "image/png", "image/heic", "image/webp"];

/// POST /api/orders — store a merchant order manifest. The body is the exact JSON
/// document; its keccak256 becomes the orderRef the escrow receives in pay(). The bytes
/// are stored verbatim so any client can rehash what it fetches. Deployment fields must
/// match this backend's deployment: a manifest for another chain or escrow is useless
/// here and likely a client bug. Merchant wallet-signature authorization is a known
/// follow-up; content addressing already makes stored manifests tamper-evident.
pub async fn put_manifest(
    store: web::Data<OrderStore>,
    config: web::Data<AppConfig>,
    body: web::Bytes,
) -> HttpResponse {
    if body.is_empty() {
        return HttpResponse::BadRequest().json(json!({ "error": "empty body" }));
    }
    let manifest = match parse_manifest(&body) {
        Ok(m) => m,
        Err(e) => {
            return HttpResponse::UnprocessableEntity().json(json!({ "error": e.to_string() }))
        }
    };
    if manifest.chain_id != config.chain_id {
        return HttpResponse::UnprocessableEntity().json(json!({
            "error": format!("manifest chainId {} does not match {}", manifest.chain_id, config.chain_id),
        }));
    }
    let escrow = format!("{:#x}", config.escrow);
    if !manifest.escrow.eq_ignore_ascii_case(&escrow) {
        return HttpResponse::UnprocessableEntity()
            .json(json!({ "error": "manifest escrow does not match this deployment" }));
    }
    // The image must already be uploaded: a manifest referencing a missing blob would
    // give the buyer an order it can never fully verify.
    if let Some(hash) = &manifest.image_hash {
        if !store.has_image(hash) {
            return HttpResponse::UnprocessableEntity()
                .json(json!({ "error": "imageHash references an image that was not uploaded" }));
        }
    }
    match store.put_manifest(&body) {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(e) => {
            tracing::error!("put_manifest: {e:#}");
            HttpResponse::InternalServerError().json(json!({ "error": "store failed" }))
        }
    }
}

/// GET /api/orders/{orderRef} — the exact manifest bytes. The buyer verifies by
/// rehashing: keccak256(body) must equal the orderRef it scanned and the one on-chain.
pub async fn get_manifest(store: web::Data<OrderStore>, path: web::Path<String>) -> HttpResponse {
    match store.get_manifest_bytes(&path.into_inner()) {
        Ok(Some(bytes)) => HttpResponse::Ok()
            .content_type("application/json")
            .body(bytes),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "order not found" })),
        Err(e) => HttpResponse::BadRequest().json(json!({ "error": e.to_string() })),
    }
}

/// POST /api/orders/image — store a product image, content-addressed by keccak256.
/// Uploaded before the manifest so the manifest can reference the returned hash.
pub async fn put_image(
    store: web::Data<OrderStore>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    if body.is_empty() {
        return HttpResponse::BadRequest().json(json!({ "error": "empty body" }));
    }
    let content_type = req
        .headers()
        .get(CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();
    if !IMAGE_TYPES.contains(&content_type.as_str()) {
        return HttpResponse::UnsupportedMediaType().json(json!({
            "error": format!("content-type must be one of {}", IMAGE_TYPES.join(", ")),
        }));
    }
    match store.put_image(&body, &content_type) {
        Ok(stored) => HttpResponse::Ok().json(stored),
        Err(e) => {
            tracing::error!("put_image: {e:#}");
            HttpResponse::InternalServerError().json(json!({ "error": "store failed" }))
        }
    }
}

/// GET /api/orders/image/{hash} — fetch a product image by hash. The buyer rehashes the
/// bytes against the manifest's imageHash before showing it.
pub async fn get_image(store: web::Data<OrderStore>, path: web::Path<String>) -> HttpResponse {
    match store.get_image(&path.into_inner()) {
        Ok(Some(image)) => HttpResponse::Ok()
            .content_type(image.content_type)
            .body(image.bytes),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "image not found" })),
        Err(e) => HttpResponse::BadRequest().json(json!({ "error": e.to_string() })),
    }
}
