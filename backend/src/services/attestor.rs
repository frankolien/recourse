use alloy::network::EthereumWallet;
use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::signers::local::PrivateKeySigner;
use alloy::signers::SignerSync;
use alloy::sol;
use alloy::sol_types::{eip712_domain, Eip712Domain, SolStruct};
use anyhow::{anyhow, Context, Result};
use std::time::{SystemTime, UNIX_EPOCH};

// The attestor signs one objective fact only: delivery status (R4, PRD "arbiter has
// no discretion"). It never decides the outcome; the escrow's PolicyEngine computes
// the verdict from the attested value. DELIVERY_STATUS: 0 UNKNOWN, 1 DELIVERED,
// 2 NOT_DELIVERED.
const ATT_TYPE_DELIVERY: u8 = 1;

sol! {
    // The EIP-712 message the escrow verifies. Field order and the third field's name
    // (`value`, not `attValue`) are load-bearing: they must match
    // RecourseEscrow.ATTESTATION_TYPEHASH exactly or the recovered signer will not be
    // the attestor and submitAttestation reverts with BadAttestor.
    struct Attestation {
        uint256 paymentId;
        uint8 attType;
        uint8 value;
        uint64 deadline;
    }

    #[sol(rpc)]
    interface IEscrowWrite {
        function submitAttestation(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline, bytes sig) external;
        function resolve(uint256 paymentId) external;
        function attestationDigest(uint256 paymentId, uint8 attType, uint8 value, uint64 deadline) external view returns (bytes32);
    }
}

#[derive(Clone)]
pub struct AttestorClient {
    // Provider carries the attestor wallet, so it both reads and signs/sends txs.
    provider: DynProvider,
    // Same key, kept separately to EIP-712-sign the attestation digest (a message
    // signature, distinct from the transaction signature the wallet produces).
    signer: PrivateKeySigner,
    escrow: Address,
    chain_id: u64,
}

pub struct AttestOutcome {
    pub attestation_tx: String,
    pub digest: String,
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

impl AttestorClient {
    pub fn new(rpc_url: &str, escrow: Address, chain_id: u64, private_key: &str) -> Result<Self> {
        let signer: PrivateKeySigner = private_key.trim().parse().context("parsing ATTESTOR_PK")?;
        let wallet = EthereumWallet::from(signer.clone());
        let url = rpc_url.parse().context("parsing RPC URL for attestor")?;
        let provider = ProviderBuilder::new()
            .wallet(wallet)
            .connect_http(url)
            .erased();
        Ok(Self {
            provider,
            signer,
            escrow,
            chain_id,
        })
    }

    pub fn attestor_address(&self) -> Address {
        self.signer.address()
    }

    fn domain(&self) -> Eip712Domain {
        eip712_domain! {
            name: "RecourseAttestor",
            version: "1",
            chain_id: self.chain_id,
            verifying_contract: self.escrow,
        }
    }

    // Boot guard: confirm our locally computed EIP-712 digest equals the escrow's, so
    // a wrong escrow address or chainId fails loudly here rather than as a cryptic
    // BadAttestor revert at attest time. Read-only.
    pub async fn self_check(&self) -> Result<()> {
        let deadline = 4_000_000_000u64;
        let sample = Attestation {
            paymentId: U256::from(1u64),
            attType: ATT_TYPE_DELIVERY,
            value: 2,
            deadline,
        };
        let local = sample.eip712_signing_hash(&self.domain());
        let escrow = IEscrowWrite::new(self.escrow, &self.provider);
        let onchain = escrow
            .attestationDigest(U256::from(1u64), ATT_TYPE_DELIVERY, 2, deadline)
            .call()
            .await
            .context("reading escrow attestationDigest")?;
        if local != onchain {
            return Err(anyhow!(
                "attestation digest mismatch (local {local:#x} vs onchain {onchain:#x}); check escrow address and chainId in deployments"
            ));
        }
        Ok(())
    }

    // Sign a delivery attestation for a payment and submit it. Moves no funds: it only
    // stores attType/attValue on the Payment (the escrow keeps status Disputed). A
    // separate resolve() settles.
    pub async fn attest(&self, payment_id: u64, value: u8) -> Result<AttestOutcome> {
        let deadline = now_secs() + 3600;
        let att = Attestation {
            paymentId: U256::from(payment_id),
            attType: ATT_TYPE_DELIVERY,
            value,
            deadline,
        };
        let sig = self.sign_attestation(&att)?;
        let escrow = IEscrowWrite::new(self.escrow, &self.provider);
        let receipt = escrow
            .submitAttestation(
                U256::from(payment_id),
                ATT_TYPE_DELIVERY,
                value,
                deadline,
                sig,
            )
            .send()
            .await
            .context("sending submitAttestation")?
            .get_receipt()
            .await
            .context("awaiting submitAttestation receipt")?;
        Ok(AttestOutcome {
            attestation_tx: format!("{:#x}", receipt.transaction_hash),
            digest: format!("{:#x}", att.eip712_signing_hash(&self.domain())),
        })
    }

    // Settle a disputed payment. Moves funds (redeems shares, splits USDC per the
    // onchain verdict), so callers must treat this as money-moving (R13) and log it.
    pub async fn resolve(&self, payment_id: u64) -> Result<String> {
        let escrow = IEscrowWrite::new(self.escrow, &self.provider);
        let receipt = escrow
            .resolve(U256::from(payment_id))
            .send()
            .await
            .context("sending resolve")?
            .get_receipt()
            .await
            .context("awaiting resolve receipt")?;
        Ok(format!("{:#x}", receipt.transaction_hash))
    }

    // Produce the 65-byte signature the escrow's raw ecrecover expects: r(32) ‖ s(32)
    // ‖ v(1) with v in {27,28}. The signer emits canonical low-s (EIP-2); we only need
    // to map the y-parity to the legacy v.
    fn sign_attestation(&self, att: &Attestation) -> Result<Bytes> {
        // Sign the prehashed EIP-712 digest directly; eip712_signing_hash is the exact
        // value the golden test pins to the escrow's onchain attestationDigest.
        let digest = att.eip712_signing_hash(&self.domain());
        let sig = self
            .signer
            .sign_hash_sync(&digest)
            .context("signing attestation")?;
        Ok(Bytes::from(encode_sig(&sig)))
    }
}

fn encode_sig(sig: &alloy::primitives::Signature) -> [u8; 65] {
    let mut raw = [0u8; 65];
    raw[..32].copy_from_slice(&sig.r().to_be_bytes::<32>());
    raw[32..64].copy_from_slice(&sig.s().to_be_bytes::<32>());
    raw[64] = 27 + sig.v() as u8;
    raw
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::primitives::{address, b256};

    fn test_domain() -> Eip712Domain {
        eip712_domain! {
            name: "RecourseAttestor",
            version: "1",
            chain_id: 5042002u64,
            verifying_contract: address!("61Fd99789B28582882a3369E2024AeaE5b5D2DC0"),
        }
    }

    // Golden value from `cast call <escrow> attestationDigest(5,1,2,4000000000)` on
    // Arc testnet. If this drifts, the signer no longer matches the deployed contract.
    #[test]
    fn digest_matches_onchain() {
        let att = Attestation {
            paymentId: U256::from(5u64),
            attType: 1,
            value: 2,
            deadline: 4_000_000_000u64,
        };
        let got = att.eip712_signing_hash(&test_domain());
        assert_eq!(
            got,
            b256!("6132a1316846f33d5f241f793988e1d0eeaf5a53c0b292560654b1b92102a25d")
        );
    }

    // The signature must recover to the signer, and the v byte must be the legacy
    // 27/28 the contract's ecrecover requires.
    #[test]
    fn signature_recovers_with_legacy_v() {
        let signer = PrivateKeySigner::random();
        let att = Attestation {
            paymentId: U256::from(7u64),
            attType: 1,
            value: 1,
            deadline: 4_000_000_000u64,
        };
        let digest = att.eip712_signing_hash(&test_domain());
        let sig = signer.sign_hash_sync(&digest).unwrap();
        let raw = encode_sig(&sig);
        assert!(raw[64] == 27 || raw[64] == 28, "v byte must be 27 or 28");
        assert_eq!(
            sig.recover_address_from_prehash(&digest).unwrap(),
            signer.address()
        );
    }
}
