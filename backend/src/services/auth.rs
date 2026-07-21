use alloy::primitives::{keccak256, Address, Signature, B256, U256};
use alloy::sol;
use alloy::sol_types::{eip712_domain, Eip712Domain, SolStruct};
use rand::RngCore;
use serde::Deserialize;
use sqlx::PgPool;
use std::str::FromStr;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::services::chain::ChainClient;

// The EIP-712 message a buyer signs to authorize a write (evidence upload or manifest).
// Field names and order are part of the type hash, so the iOS and web clients must use
// exactly this shape:
//   Authorization(string action,uint256 paymentId,address walletAddress,uint256 chainId,bytes32 bodyHash,bytes32 nonce,uint256 expiresAt)
// Domain: name "Recourse", version "1", chainId (no verifyingContract; this is an
// off-chain authorization, not a contract call).
sol! {
    struct Authorization {
        string action;
        uint256 paymentId;
        address walletAddress;
        uint256 chainId;
        bytes32 bodyHash;
        bytes32 nonce;
        uint256 expiresAt;
    }
}

// The signed envelope the caller sends (base64 JSON in the X-Recourse-Auth header).
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AuthEnvelope {
    pub action: String,
    pub payment_id: i64,
    pub wallet_address: String,
    pub chain_id: u64,
    pub body_hash: String,
    pub nonce: String,
    pub expires_at: i64,
    pub signature: String,
}

// Auth failures carry the HTTP status the handler should return, so the mapping to a
// response stays in one place without pulling actix into this service.
#[derive(Debug)]
pub enum AuthError {
    Malformed(String),    // 400: the envelope itself is unparseable
    Unauthorized(String), // 401: signature, nonce, or freshness failed
    Forbidden(String),    // 403: valid signature, but not this payment's buyer
    Upstream(String),     // 502: could not read the chain to check the buyer
    Internal(String),     // 500: our own storage failed
}

impl AuthError {
    pub fn parts(&self) -> (u16, String) {
        match self {
            AuthError::Malformed(m) => (400, m.clone()),
            AuthError::Unauthorized(m) => (401, m.clone()),
            AuthError::Forbidden(m) => (403, m.clone()),
            AuthError::Upstream(m) => (502, m.clone()),
            AuthError::Internal(m) => (500, m.clone()),
        }
    }
}

pub const CHALLENGE_TTL_SECS: i64 = 300; // 5 minutes

pub struct Challenge {
    pub nonce: String,
    pub expires_at: i64,
}

fn now_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn domain(chain_id: u64) -> Eip712Domain {
    eip712_domain! {
        name: "Recourse",
        version: "1",
        chain_id: chain_id,
    }
}

// Issue a fresh single-use challenge, pruning expired rows so the table stays small.
pub async fn issue_challenge(pool: &PgPool) -> Result<Challenge, AuthError> {
    let now = now_secs();
    let expires_at = now + CHALLENGE_TTL_SECS;
    let mut raw = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut raw);
    let nonce = format!("{:#x}", B256::from(raw));

    let _ = sqlx::query("DELETE FROM auth_challenges WHERE expires_at < $1")
        .bind(now)
        .execute(pool)
        .await;
    sqlx::query("INSERT INTO auth_challenges (nonce, expires_at) VALUES ($1, $2)")
        .bind(&nonce)
        .bind(expires_at)
        .execute(pool)
        .await
        .map_err(|e| AuthError::Internal(format!("issuing challenge: {e}")))?;
    Ok(Challenge { nonce, expires_at })
}

// Verify a buyer-signed envelope for `expected_action` over `body`, then consume the
// nonce so the signature cannot be replayed. Returns the buyer address on success. The
// order matters: every cheap or non-destructive check runs first, and the nonce is only
// burned once everything else (including that the signer is the on-chain buyer) passes.
pub async fn verify_buyer(
    pool: &PgPool,
    chain: &ChainClient,
    expected_chain_id: u64,
    envelope: &AuthEnvelope,
    expected_action: &str,
    body: &[u8],
) -> Result<Address, AuthError> {
    if envelope.action != expected_action {
        return Err(AuthError::Unauthorized(format!(
            "action mismatch: expected {expected_action}"
        )));
    }
    if envelope.chain_id != expected_chain_id {
        return Err(AuthError::Unauthorized("chainId mismatch".into()));
    }
    if envelope.payment_id <= 0 {
        return Err(AuthError::Malformed("invalid paymentId".into()));
    }
    let now = now_secs();
    if envelope.expires_at <= now {
        return Err(AuthError::Unauthorized("authorization expired".into()));
    }

    // The signature commits to the exact request body via its keccak256, so a valid
    // envelope cannot be reused to authorize different bytes.
    let body_hash = format!("{:#x}", keccak256(body));
    if !envelope.body_hash.eq_ignore_ascii_case(&body_hash) {
        return Err(AuthError::Unauthorized(
            "bodyHash does not match request body".into(),
        ));
    }

    let wallet = parse_address(&envelope.wallet_address)?;
    let msg = Authorization {
        action: envelope.action.clone(),
        paymentId: U256::from(envelope.payment_id as u64),
        walletAddress: wallet,
        chainId: U256::from(expected_chain_id),
        bodyHash: parse_b256(&envelope.body_hash)?,
        nonce: parse_b256(&envelope.nonce)?,
        expiresAt: U256::from(envelope.expires_at as u64),
    };
    let digest = msg.eip712_signing_hash(&domain(expected_chain_id));
    let sig = parse_sig(&envelope.signature)?;
    let recovered = sig
        .recover_address_from_prehash(&digest)
        .map_err(|e| AuthError::Unauthorized(format!("bad signature: {e}")))?;
    if recovered != wallet {
        return Err(AuthError::Unauthorized(
            "signature does not match walletAddress".into(),
        ));
    }

    // Authorization proper: the signer must be the payment's on-chain buyer. A policyId
    // of 0 means the payment does not exist (getPayment returns a zeroed record).
    let payment = chain
        .get_payment(envelope.payment_id as u64)
        .await
        .map_err(|e| AuthError::Upstream(format!("chain read failed: {e}")))?;
    if payment.policy_id == 0 {
        return Err(AuthError::Forbidden("payment does not exist".into()));
    }
    let buyer = parse_address(&payment.buyer)?;
    if recovered != buyer {
        return Err(AuthError::Forbidden(
            "signer is not the payment buyer".into(),
        ));
    }

    // Replay gate: consume the nonce atomically. Only one concurrent request can flip
    // consumed to true, so a captured envelope is good for exactly one write.
    let consumed = sqlx::query_scalar::<_, String>(
        "UPDATE auth_challenges SET consumed = TRUE \
         WHERE nonce = $1 AND consumed = FALSE AND expires_at > $2 \
         RETURNING nonce",
    )
    .bind(&envelope.nonce)
    .bind(now)
    .fetch_optional(pool)
    .await
    .map_err(|e| AuthError::Internal(format!("consuming nonce: {e}")))?;
    if consumed.is_none() {
        return Err(AuthError::Unauthorized(
            "nonce invalid, expired, or already used".into(),
        ));
    }

    Ok(recovered)
}

// Addresses are lowercased before parsing so a non-checksummed value still parses; the
// 20 encoded bytes (and thus the signed digest) are identical either way.
fn parse_address(s: &str) -> Result<Address, AuthError> {
    Address::from_str(&s.trim().to_lowercase())
        .map_err(|_| AuthError::Malformed(format!("invalid address: {s}")))
}

fn parse_b256(s: &str) -> Result<B256, AuthError> {
    B256::from_str(s.trim()).map_err(|_| AuthError::Malformed(format!("invalid bytes32: {s}")))
}

fn parse_sig(s: &str) -> Result<Signature, AuthError> {
    Signature::from_str(s.trim())
        .map_err(|e| AuthError::Malformed(format!("invalid signature: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::primitives::{address, b256};
    use alloy::signers::local::PrivateKeySigner;
    use alloy::signers::SignerSync;

    fn sample() -> Authorization {
        Authorization {
            action: "evidence.manifest".to_string(),
            paymentId: U256::from(10u64),
            walletAddress: address!("00000000000000000000000000000000000000ab"),
            chainId: U256::from(5042002u64),
            bodyHash: b256!("1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"),
            nonce: b256!("00000000000000000000000000000000000000000000000000000000000000ff"),
            expiresAt: U256::from(4_000_000_000u64),
        }
    }

    // Golden from viem hashTypedData over the same domain, types, and message. Locks the
    // alloy encoding to exactly what the web and iOS clients sign; any drift here would
    // reject every real signature.
    #[test]
    fn digest_matches_viem() {
        let got = sample().eip712_signing_hash(&domain(5042002));
        assert_eq!(
            got,
            b256!("ab9ccaee667c989b0f204c16aa493a357f48a6ad44e3c7c161a69a543654ad7a")
        );
    }

    // A signature over the digest recovers to the signer, and parse_sig round-trips the
    // 65-byte hex the clients send.
    #[test]
    fn signature_recovers_to_signer() {
        let signer = PrivateKeySigner::random();
        let digest = sample().eip712_signing_hash(&domain(5042002));
        let sig = signer.sign_hash_sync(&digest).unwrap();
        let hex = format!(
            "0x{}",
            sig.as_bytes()
                .iter()
                .map(|b| format!("{b:02x}"))
                .collect::<String>()
        );
        let parsed = parse_sig(&hex).unwrap();
        assert_eq!(
            parsed.recover_address_from_prehash(&digest).unwrap(),
            signer.address()
        );
    }
}
