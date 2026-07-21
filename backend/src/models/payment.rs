use chrono::{DateTime, Utc};
use serde::Serialize;

// The read model for a payment: the projection row the API serves. Verdict columns are
// nullable because they only exist once a claim is filed (from the onchain
// previewVerdict, R2). Amounts are u128 base units kept as text (R1).
#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct PaymentRow {
    pub payment_id: i64,
    pub buyer: String,
    pub merchant: String,
    pub beneficiary: String,
    pub policy_id: i64,
    pub amount: String,
    pub shares: String,
    pub paid_at: i64,
    pub filed_at: i64,
    pub claim_type: i32,
    pub evidence_mask: i32,
    pub att_type: i32,
    pub att_value: i32,
    pub evidence_root: String,
    pub verdict_bps: i32,
    pub status: i32,
    pub refund_bps: Option<i32>,
    pub requires_return: Option<bool>,
    pub rule_index: Option<i32>,
    pub matched: Option<bool>,
    pub verdict_hash: Option<String>,
    pub updated_at: DateTime<Utc>,
}
