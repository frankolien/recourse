use crate::chain::{PaymentState, PolicyState, VerdictState};
use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::postgres::{PgPool, PgPoolOptions};

pub async fn connect(database_url: &str) -> Result<PgPool> {
    let pool = PgPoolOptions::new().max_connections(5).connect(database_url).await?;
    sqlx::raw_sql(include_str!("../migrations/0001_init.sql")).execute(&pool).await?;
    Ok(pool)
}

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

pub async fn upsert_payment(pool: &PgPool, p: &PaymentState, v: Option<&VerdictState>) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO payments (
            payment_id, buyer, merchant, beneficiary, policy_id, amount, shares,
            paid_at, filed_at, claim_type, evidence_mask, att_type, att_value,
            evidence_root, verdict_bps, status,
            refund_bps, requires_return, rule_index, matched, verdict_hash, updated_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21, now())
        ON CONFLICT (payment_id) DO UPDATE SET
            buyer = EXCLUDED.buyer,
            merchant = EXCLUDED.merchant,
            beneficiary = EXCLUDED.beneficiary,
            policy_id = EXCLUDED.policy_id,
            amount = EXCLUDED.amount,
            shares = EXCLUDED.shares,
            paid_at = EXCLUDED.paid_at,
            filed_at = EXCLUDED.filed_at,
            claim_type = EXCLUDED.claim_type,
            evidence_mask = EXCLUDED.evidence_mask,
            att_type = EXCLUDED.att_type,
            att_value = EXCLUDED.att_value,
            evidence_root = EXCLUDED.evidence_root,
            verdict_bps = EXCLUDED.verdict_bps,
            status = EXCLUDED.status,
            refund_bps = EXCLUDED.refund_bps,
            requires_return = EXCLUDED.requires_return,
            rule_index = EXCLUDED.rule_index,
            matched = EXCLUDED.matched,
            verdict_hash = EXCLUDED.verdict_hash,
            updated_at = now()
        "#,
    )
    .bind(p.payment_id)
    .bind(&p.buyer)
    .bind(&p.merchant)
    .bind(&p.beneficiary)
    .bind(p.policy_id)
    .bind(&p.amount)
    .bind(&p.shares)
    .bind(p.paid_at)
    .bind(p.filed_at)
    .bind(p.claim_type)
    .bind(p.evidence_mask)
    .bind(p.att_type)
    .bind(p.att_value)
    .bind(&p.evidence_root)
    .bind(p.verdict_bps)
    .bind(p.status)
    .bind(v.map(|x| x.refund_bps))
    .bind(v.map(|x| x.requires_return))
    .bind(v.map(|x| x.rule_index))
    .bind(v.map(|x| x.matched))
    .bind(v.map(|x| x.verdict_hash.clone()))
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn upsert_policy(pool: &PgPool, p: &PolicyState) -> Result<()> {
    sqlx::query(
        r#"
        INSERT INTO policies (policy_id, merchant, dispute_window, default_refund_bps, policy_hash, rules, updated_at)
        VALUES ($1,$2,$3,$4,$5,$6, now())
        ON CONFLICT (policy_id) DO UPDATE SET
            merchant = EXCLUDED.merchant,
            dispute_window = EXCLUDED.dispute_window,
            default_refund_bps = EXCLUDED.default_refund_bps,
            policy_hash = EXCLUDED.policy_hash,
            rules = EXCLUDED.rules,
            updated_at = now()
        "#,
    )
    .bind(p.policy_id)
    .bind(&p.merchant)
    .bind(p.dispute_window)
    .bind(p.default_refund_bps)
    .bind(&p.policy_hash)
    .bind(&p.rules)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn list_payments(pool: &PgPool, merchant: Option<String>) -> Result<Vec<PaymentRow>> {
    let rows = sqlx::query_as::<_, PaymentRow>(
        "SELECT * FROM payments WHERE ($1::text IS NULL OR merchant = lower($1)) ORDER BY payment_id DESC",
    )
    .bind(merchant)
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get_payment(pool: &PgPool, id: i64) -> Result<Option<PaymentRow>> {
    let row = sqlx::query_as::<_, PaymentRow>("SELECT * FROM payments WHERE payment_id = $1")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}

pub async fn list_disputes(pool: &PgPool) -> Result<Vec<PaymentRow>> {
    let rows = sqlx::query_as::<_, PaymentRow>("SELECT * FROM payments WHERE filed_at <> 0 ORDER BY filed_at DESC")
        .fetch_all(pool)
        .await?;
    Ok(rows)
}

pub async fn list_policies(pool: &PgPool) -> Result<Vec<PolicyRow>> {
    let rows = sqlx::query_as::<_, PolicyRow>("SELECT * FROM policies ORDER BY policy_id DESC")
        .fetch_all(pool)
        .await?;
    Ok(rows)
}

pub async fn get_policy(pool: &PgPool, id: i64) -> Result<Option<PolicyRow>> {
    let row = sqlx::query_as::<_, PolicyRow>("SELECT * FROM policies WHERE policy_id = $1")
        .bind(id)
        .fetch_optional(pool)
        .await?;
    Ok(row)
}

pub async fn count_payments(pool: &PgPool) -> Result<i64> {
    let count: (i64,) = sqlx::query_as("SELECT count(*) FROM payments").fetch_one(pool).await?;
    Ok(count.0)
}
