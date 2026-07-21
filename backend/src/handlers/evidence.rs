use actix_web::http::header::CONTENT_TYPE;
use actix_web::{web, HttpRequest, HttpResponse};
use alloy::primitives::B256;
use serde::Deserialize;
use serde_json::json;
use sqlx::PgPool;

use crate::handlers::auth::{error_response, extract_envelope};
use crate::services::auth as svc_auth;
use crate::services::chain::ChainClient;
use crate::services::evidence::{
    compute_evidence_root, EvidenceManifest, EvidenceStore, ManifestItem,
};
use crate::services::AppConfig;

// Manifests are filed under one key per deployment so a redeploy's payment ids can't
// collide with an earlier deployment's (paymentIds restart at 1 on a fresh escrow).
fn deployment_key(config: &AppConfig) -> String {
    format!("{}_{:#x}", config.chain_id, config.escrow)
}

/// POST /api/evidence — store an evidence blob, returns its keccak256 hash (the value a
/// buyer pins on-chain as EvidenceItem.hash). Authorized: the caller signs an EIP-712
/// envelope proving they are the on-chain buyer of the referenced payment (action
/// "evidence.upload"), so the store is not an open dumping ground.
pub async fn put_evidence(
    pool: web::Data<PgPool>,
    chain: web::Data<ChainClient>,
    config: web::Data<AppConfig>,
    store: web::Data<EvidenceStore>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    if body.is_empty() {
        return HttpResponse::BadRequest().json(json!({ "error": "empty body" }));
    }
    let envelope = match extract_envelope(&req) {
        Ok(e) => e,
        Err((code, msg)) => return error_response(code, &msg),
    };
    if let Err(e) = svc_auth::verify_buyer(
        pool.get_ref(),
        chain.get_ref(),
        config.chain_id,
        &envelope,
        "evidence.upload",
        &body,
    )
    .await
    {
        let (code, msg) = e.parts();
        return error_response(code, &msg);
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
pub async fn get_evidence(
    store: web::Data<EvidenceStore>,
    path: web::Path<String>,
) -> HttpResponse {
    match store.get(&path.into_inner()) {
        Ok(Some(blob)) => HttpResponse::Ok()
            .content_type(blob.content_type)
            .body(blob.bytes),
        Ok(None) => HttpResponse::NotFound().json(json!({ "error": "evidence not found" })),
        Err(e) => HttpResponse::BadRequest().json(json!({ "error": e.to_string() })),
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ManifestBody {
    pub payment_id: i64,
    pub items: Vec<ManifestItem>,
}

/// POST /api/evidence/manifest — record the ordered evidence list for a payment, but only
/// if its fold reproduces the escrow's onchain evidenceRoot. Authorized: the caller signs
/// an EIP-712 envelope (action "evidence.manifest") proving they are the payment's buyer,
/// and the signed bodyHash commits to this exact JSON. Verification reads the live chain
/// (not the projection), so it is trustless and free of indexer lag.
pub async fn verify_manifest(
    pool: web::Data<PgPool>,
    chain: web::Data<ChainClient>,
    store: web::Data<EvidenceStore>,
    config: web::Data<AppConfig>,
    req: HttpRequest,
    body: web::Bytes,
) -> HttpResponse {
    let envelope = match extract_envelope(&req) {
        Ok(e) => e,
        Err((code, msg)) => return error_response(code, &msg),
    };
    let parsed: ManifestBody = match serde_json::from_slice(&body) {
        Ok(b) => b,
        Err(e) => {
            return HttpResponse::BadRequest()
                .json(json!({ "error": format!("invalid JSON: {e}") }))
        }
    };
    if parsed.payment_id <= 0 {
        return HttpResponse::BadRequest().json(json!({ "error": "invalid paymentId" }));
    }
    if envelope.payment_id != parsed.payment_id {
        return error_response(401, "authorization paymentId does not match body");
    }
    // Buyer authorization also proves the payment exists (rejects a zeroed record).
    if let Err(e) = svc_auth::verify_buyer(
        pool.get_ref(),
        chain.get_ref(),
        config.chain_id,
        &envelope,
        "evidence.manifest",
        &body,
    )
    .await
    {
        let (code, msg) = e.parts();
        return error_response(code, &msg);
    }

    let computed = match compute_evidence_root(&parsed.items) {
        Ok(r) => format!("{r:#x}"),
        Err(e) => return HttpResponse::BadRequest().json(json!({ "error": e.to_string() })),
    };
    let onchain = match chain.get_payment(parsed.payment_id as u64).await {
        Ok(p) => p.evidence_root,
        Err(e) => {
            tracing::error!("verify_manifest: chain read failed: {e:#}");
            return HttpResponse::BadGateway().json(json!({ "error": "chain read failed" }));
        }
    };
    if !computed.eq_ignore_ascii_case(&onchain) {
        return HttpResponse::UnprocessableEntity().json(json!({
            "paymentId": parsed.payment_id,
            "matches": false,
            "computedRoot": computed,
            "onchainRoot": onchain,
            "error": "manifest does not reconstruct the onchain evidenceRoot",
        }));
    }
    let manifest = EvidenceManifest {
        payment_id: parsed.payment_id,
        evidence_root: onchain.clone(),
        items: parsed.items,
    };
    if let Err(e) = store.put_manifest(&deployment_key(&config), &manifest) {
        tracing::error!("verify_manifest: persist failed: {e:#}");
        return HttpResponse::InternalServerError().json(json!({ "error": "persist failed" }));
    }
    HttpResponse::Ok().json(json!({
        "paymentId": parsed.payment_id,
        "matches": true,
        "computedRoot": computed,
        "onchainRoot": onchain,
        "items": manifest.items,
    }))
}

/// GET /api/payments/{id}/evidence — the payment's verified evidence list. The stored
/// manifest is re-folded and re-checked against the live onchain root on every read, so a
/// manifest tampered on disk is caught here, not trusted.
pub async fn get_payment_evidence(
    chain: web::Data<ChainClient>,
    store: web::Data<EvidenceStore>,
    config: web::Data<AppConfig>,
    path: web::Path<i64>,
) -> HttpResponse {
    let payment_id = path.into_inner();
    if payment_id <= 0 {
        return HttpResponse::BadRequest().json(json!({ "error": "invalid paymentId" }));
    }
    let onchain = match chain.get_payment(payment_id as u64).await {
        // A policyId of 0 means the payment does not exist (getPayment zeroes the record),
        // so do not answer as if it had empty evidence.
        Ok(p) if p.policy_id == 0 => {
            return HttpResponse::NotFound().json(json!({ "error": "payment not found" }))
        }
        Ok(p) => p.evidence_root,
        Err(e) => {
            tracing::error!("get_payment_evidence: chain read failed: {e:#}");
            return HttpResponse::BadGateway().json(json!({ "error": "chain read failed" }));
        }
    };
    let manifest = match store.get_manifest(&deployment_key(&config), payment_id) {
        Ok(m) => m,
        Err(e) => {
            tracing::error!("get_payment_evidence: manifest load failed: {e:#}");
            return HttpResponse::InternalServerError()
                .json(json!({ "error": "manifest load failed" }));
        }
    };
    let Some(manifest) = manifest else {
        // No manifest on file; that is only consistent if the chain also holds no evidence.
        let empty = format!("{:#x}", B256::ZERO);
        return HttpResponse::Ok().json(json!({
            "paymentId": payment_id,
            "evidenceRoot": onchain,
            "hasManifest": false,
            "matches": onchain.eq_ignore_ascii_case(&empty),
            "items": [],
        }));
    };
    let computed = match compute_evidence_root(&manifest.items) {
        Ok(r) => format!("{r:#x}"),
        Err(e) => {
            return HttpResponse::InternalServerError().json(json!({ "error": e.to_string() }))
        }
    };
    let items: Vec<_> = manifest
        .items
        .iter()
        .map(|it| {
            let (available, size, content_type) = match store.stat(&it.hash) {
                Ok(Some((sz, ct))) => (true, Some(sz), Some(ct)),
                _ => (false, None, None),
            };
            json!({
                "evType": it.ev_type,
                "hash": it.hash,
                "available": available,
                "size": size,
                "contentType": content_type,
            })
        })
        .collect();
    HttpResponse::Ok().json(json!({
        "paymentId": payment_id,
        "evidenceRoot": onchain,
        "hasManifest": true,
        "matches": computed.eq_ignore_ascii_case(&onchain),
        "computedRoot": computed,
        "items": items,
    }))
}
