use actix_web::{web, HttpResponse};
use serde::Deserialize;
use serde_json::json;

use crate::services::attestor::AttestorClient;

// Demo-only endpoints (R6), gated behind DEMO_MODE via the presence of the attestor
// (built only when DEMO_MODE and a key are set). The attestor signs objective delivery
// facts and pushes txs; it never decides outcomes (the onchain PolicyEngine does).

const DISABLED: &str = "attestor disabled; set DEMO_MODE=true and ATTESTOR_PK";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AttestBody {
    pub payment_id: u64,
    // Delivery status: 1 DELIVERED, 2 NOT_DELIVERED.
    pub value: u8,
}

/// POST /api/demo/attest — sign a delivery attestation and submit it (moves no funds).
pub async fn attest(attestor: web::Data<Option<AttestorClient>>, body: web::Json<AttestBody>) -> HttpResponse {
    let Some(attestor) = attestor.get_ref().as_ref() else {
        return HttpResponse::ServiceUnavailable().json(json!({ "error": DISABLED }));
    };
    if !(1..=2).contains(&body.value) {
        return HttpResponse::BadRequest()
            .json(json!({ "error": "value must be 1 (DELIVERED) or 2 (NOT_DELIVERED)" }));
    }
    // R8: log every attestor action against the deployment.
    tracing::info!("DEMO attest: payment {} value {}", body.payment_id, body.value);
    match attestor.attest(body.payment_id, body.value).await {
        Ok(out) => HttpResponse::Ok().json(json!({
            "demo": true,
            "paymentId": body.payment_id,
            "value": body.value,
            "attestationTx": out.attestation_tx,
            "digest": out.digest,
        })),
        Err(e) => {
            tracing::error!("demo attest: {e:#}");
            HttpResponse::InternalServerError().json(json!({ "error": "attestation failed" }))
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolveBody {
    pub payment_id: u64,
}

/// POST /api/demo/resolve — settle a disputed payment (moves funds; logged, R8).
pub async fn resolve(attestor: web::Data<Option<AttestorClient>>, body: web::Json<ResolveBody>) -> HttpResponse {
    let Some(attestor) = attestor.get_ref().as_ref() else {
        return HttpResponse::ServiceUnavailable().json(json!({ "error": DISABLED }));
    };
    tracing::info!("DEMO resolve (settlement): payment {}", body.payment_id);
    match attestor.resolve(body.payment_id).await {
        Ok(tx) => HttpResponse::Ok().json(json!({
            "demo": true,
            "paymentId": body.payment_id,
            "resolveTx": tx,
        })),
        Err(e) => {
            tracing::error!("demo resolve: {e:#}");
            HttpResponse::InternalServerError().json(json!({ "error": "resolve failed" }))
        }
    }
}
