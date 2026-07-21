use chrono::{DateTime, Utc};
use serde::Serialize;

// The read model for a policy: the projection row the API serves. Rules are stored as
// JSON exactly as decoded from the registry.
#[derive(Debug, Serialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct PolicyRow {
    pub policy_id: i64,
    pub merchant: String,
    pub dispute_window: i64,
    pub default_refund_bps: i32,
    pub policy_hash: String,
    pub rules: serde_json::Value,
    pub updated_at: DateTime<Utc>,
}
