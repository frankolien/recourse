use alloy::primitives::{Address, U256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::rpc::types::Filter;
use alloy::sol;
use anyhow::{anyhow, Result};

// Onchain interfaces we read. Selectors depend only on inputs, so modelling the
// enum-typed status as uint8 decodes correctly. The verdict comes from the
// contract's previewVerdict; this service never recomputes it (R2).
sol! {
    #[sol(rpc)]
    interface IEscrow {
        struct Payment {
            address buyer;
            address merchant;
            address beneficiary;
            uint256 policyId;
            uint128 amount;
            uint128 shares;
            uint64 paidAt;
            uint64 filedAt;
            uint8 claimType;
            uint16 evidenceMask;
            uint8 attType;
            uint8 attValue;
            bytes32 evidenceRoot;
            uint16 verdictBps;
            uint8 status;
        }
        struct Verdict {
            uint16 refundBps;
            bool requiresReturn;
            uint8 ruleIndex;
            bool matched;
        }
        function paymentCount() external view returns (uint256);
        function getPayment(uint256 paymentId) external view returns (Payment);
        function previewVerdict(uint256 paymentId) external view returns (Verdict v, bytes32 verdictHash);
        function resolveDelay() external view returns (uint64);
    }

    #[sol(rpc)]
    interface IRegistry {
        struct Rule {
            uint8 claimType;
            uint16 requiredEvidenceMask;
            uint8 attType;
            uint8 attExpected;
            uint32 claimWindow;
            uint16 refundBps;
            bool requiresReturn;
        }
        struct Policy {
            address merchant;
            uint32 disputeWindow;
            uint16 defaultRefundBps;
            Rule[] rules;
        }
        function policyCount() external view returns (uint256);
        function getPolicy(uint256 policyId) external view returns (Policy);
        function policyHash(uint256 policyId) external view returns (bytes32);
    }
}

pub struct PaymentState {
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
}

pub struct VerdictState {
    pub refund_bps: i32,
    pub requires_return: bool,
    pub rule_index: i32,
    pub matched: bool,
    pub verdict_hash: String,
}

pub struct PolicyState {
    pub policy_id: i64,
    pub merchant: String,
    pub dispute_window: i64,
    pub default_refund_bps: i32,
    pub policy_hash: String,
    pub rules: serde_json::Value,
}

#[derive(Clone)]
pub struct ChainClient {
    provider: DynProvider,
    escrow: Address,
    registry: Address,
}

impl ChainClient {
    pub fn new(rpc_url: &str, escrow: Address, registry: Address) -> Result<Self> {
        let url = rpc_url.parse()?;
        let provider = ProviderBuilder::new().connect_http(url).erased();
        Ok(Self {
            provider,
            escrow,
            registry,
        })
    }

    pub async fn payment_count(&self) -> Result<u64> {
        let escrow = IEscrow::new(self.escrow, &self.provider);
        Ok(escrow.paymentCount().call().await?.to::<u64>())
    }

    pub async fn policy_count(&self) -> Result<u64> {
        let registry = IRegistry::new(self.registry, &self.provider);
        Ok(registry.policyCount().call().await?.to::<u64>())
    }

    // Min seconds an un-attested dispute must wait before resolve() will settle it. Read
    // once so the auto-resolver can tell which disputes are ready.
    pub async fn resolve_delay(&self) -> Result<u64> {
        let escrow = IEscrow::new(self.escrow, &self.provider);
        Ok(escrow.resolveDelay().call().await?)
    }

    pub async fn block_number(&self) -> Result<u64> {
        Ok(self.provider.get_block_number().await?)
    }

    pub async fn block_timestamp(&self, number: u64) -> Result<u64> {
        let block = self
            .provider
            .get_block_by_number(number.into())
            .await?
            .ok_or_else(|| anyhow!("block {number} not found"))?;
        Ok(block.header.timestamp)
    }

    // Last block whose timestamp is at or before target_ts, by binary search over
    // headers. Lets the orderRef log sweep start near a payment's paidAt instead of
    // scanning the chain from genesis.
    pub async fn block_at_or_before(&self, target_ts: u64) -> Result<u64> {
        let mut low = 0u64;
        let mut high = self.block_number().await?;
        while low < high {
            let mid = low + (high - low).div_ceil(2);
            if self.block_timestamp(mid).await? <= target_ts {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        Ok(low)
    }

    // Paid events in a block range as (paymentId, orderRef). The escrow's state never
    // stores orderRef (it is the manifest hash the buyer verified), so the event log is
    // the only onchain source for linking a payment back to its order.
    pub async fn paid_events(&self, from_block: u64, to_block: u64) -> Result<Vec<(u64, String)>> {
        let filter = Filter::new()
            .address(self.escrow)
            .event("Paid(uint256,address,address,uint256,uint128,bytes32,bytes32)")
            .from_block(from_block)
            .to_block(to_block);
        let logs = self.provider.get_logs(&filter).await?;
        let mut events = Vec::with_capacity(logs.len());
        for log in logs {
            let raw = &log.inner.data;
            let topics = raw.topics();
            // topic0 = signature, topic1 = indexed paymentId. Non-indexed data words:
            // policyId, amount, orderRef, policyHash.
            if topics.len() < 2 || raw.data.len() < 96 {
                continue;
            }
            let payment_id = U256::from_be_slice(topics[1].as_slice()).to::<u64>();
            let order_ref = format!("0x{}", alloy::hex::encode(&raw.data[64..96]));
            events.push((payment_id, order_ref));
        }
        Ok(events)
    }

    pub async fn get_payment(&self, id: u64) -> Result<PaymentState> {
        let escrow = IEscrow::new(self.escrow, &self.provider);
        let p = escrow.getPayment(U256::from(id)).call().await?;
        Ok(PaymentState {
            payment_id: id as i64,
            buyer: format!("{:#x}", p.buyer),
            merchant: format!("{:#x}", p.merchant),
            beneficiary: format!("{:#x}", p.beneficiary),
            policy_id: p.policyId.to::<u64>() as i64,
            amount: p.amount.to_string(),
            shares: p.shares.to_string(),
            paid_at: p.paidAt as i64,
            filed_at: p.filedAt as i64,
            claim_type: p.claimType as i32,
            evidence_mask: p.evidenceMask as i32,
            att_type: p.attType as i32,
            att_value: p.attValue as i32,
            evidence_root: format!("{:#x}", p.evidenceRoot),
            verdict_bps: p.verdictBps as i32,
            status: p.status as i32,
        })
    }

    pub async fn preview_verdict(&self, id: u64) -> Result<VerdictState> {
        let escrow = IEscrow::new(self.escrow, &self.provider);
        let out = escrow.previewVerdict(U256::from(id)).call().await?;
        Ok(VerdictState {
            refund_bps: out.v.refundBps as i32,
            requires_return: out.v.requiresReturn,
            rule_index: out.v.ruleIndex as i32,
            matched: out.v.matched,
            verdict_hash: format!("{:#x}", out.verdictHash),
        })
    }

    pub async fn get_policy(&self, id: u64) -> Result<PolicyState> {
        let registry = IRegistry::new(self.registry, &self.provider);
        let policy = registry.getPolicy(U256::from(id)).call().await?;
        let hash = registry.policyHash(U256::from(id)).call().await?;
        let rules: Vec<serde_json::Value> = policy
            .rules
            .iter()
            .map(|r| {
                serde_json::json!({
                    "claimType": r.claimType,
                    "requiredEvidenceMask": r.requiredEvidenceMask,
                    "attType": r.attType,
                    "attExpected": r.attExpected,
                    "claimWindow": r.claimWindow,
                    "refundBps": r.refundBps,
                    "requiresReturn": r.requiresReturn,
                })
            })
            .collect();
        Ok(PolicyState {
            policy_id: id as i64,
            merchant: format!("{:#x}", policy.merchant),
            dispute_window: policy.disputeWindow as i64,
            default_refund_bps: policy.defaultRefundBps as i32,
            policy_hash: format!("{:#x}", hash),
            rules: serde_json::Value::Array(rules),
        })
    }
}
