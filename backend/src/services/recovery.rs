//! The Recovery Key and the emailed code that releases it.
//!
//! The key is one of the three owners of an account's Safe. It is minted here, sealed
//! under a wrapping key that lives only in the environment, and unsealed for exactly
//! one job: co-signing the swap of a lost Device Key for a new one, after the person
//! has proved control of the account's email. It cannot spend, because it is one
//! signature against a threshold of two and `smart_accounts` never asks it to sign
//! anything but an owner swap.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use alloy::primitives::{Address, B256};
use alloy::signers::local::PrivateKeySigner;
use alloy::signers::SignerSync;
use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use base64::Engine;
use chrono::{DateTime, Duration, Utc};
use rand::RngCore;
use serde::Serialize;
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;

/// Names the wrapping key a row was sealed under. Bump when the key moves to a KMS so
/// old rows can be told apart and re-sealed.
const KEY_ID_ENV: &str = "env-v1";
const NONCE_BYTES: usize = 12;

const CODE_DIGITS: u32 = 6;
/// Long enough to leave the app, read the mail and come back.
const CODE_TTL: Duration = Duration::minutes(10);
/// How long a proved inbox stays proved: enough to mint a key and sign a swap, not
/// enough to keep as a standing capability.
const GRANT_TTL: Duration = Duration::minutes(15);
const MAX_ATTEMPTS: i32 = 5;
const MAX_CODES_PER_HOUR: i64 = 5;

pub const PURPOSE_DEVICE_ROTATION: &str = "device_rotation";

/// Seals and opens Recovery Keys. Holding the wrapping key is an operational control,
/// not a cryptographic impossibility: the server can open what it sealed. The property
/// the design rests on is the threshold, not this.
#[derive(Clone)]
pub struct RecoveryVault {
    key: [u8; 32],
}

impl RecoveryVault {
    /// The wrapping key is 32 random bytes, base64. Anything else is refused at boot
    /// rather than discovered at the first recovery.
    pub fn from_base64(encoded: &str) -> Result<Self, String> {
        let bytes = base64::engine::general_purpose::STANDARD
            .decode(encoded.trim())
            .map_err(|error| format!("RECOVERY_VAULT_KEY is not base64: {error}"))?;
        let key: [u8; 32] = bytes
            .try_into()
            .map_err(|_| "RECOVERY_VAULT_KEY must decode to exactly 32 bytes".to_string())?;
        Ok(Self { key })
    }

    /// Seal a secret for one account. The account id is authenticated data, so a
    /// sealed row copied onto another account fails to open there.
    fn seal(&self, account_id: i64, secret: &[u8]) -> Result<Vec<u8>, AccountAuthError> {
        let cipher = Aes256Gcm::new((&self.key).into());
        let mut nonce = [0u8; NONCE_BYTES];
        OsRng.fill_bytes(&mut nonce);
        let sealed = cipher
            .encrypt(
                Nonce::from_slice(&nonce),
                Payload {
                    msg: secret,
                    aad: &account_id.to_be_bytes(),
                },
            )
            .map_err(|_| AccountAuthError::Internal("sealing the recovery key failed".into()))?;
        let mut out = nonce.to_vec();
        out.extend_from_slice(&sealed);
        Ok(out)
    }

    fn open(&self, account_id: i64, sealed: &[u8]) -> Result<Vec<u8>, AccountAuthError> {
        if sealed.len() <= NONCE_BYTES {
            return Err(AccountAuthError::Internal("sealed recovery key is truncated".into()));
        }
        let (nonce, body) = sealed.split_at(NONCE_BYTES);
        let cipher = Aes256Gcm::new((&self.key).into());
        cipher
            .decrypt(
                Nonce::from_slice(nonce),
                Payload {
                    msg: body,
                    aad: &account_id.to_be_bytes(),
                },
            )
            .map_err(|_| AccountAuthError::Internal("the recovery key did not open".into()))
    }
}

/// Mint the account's Recovery Key, or return the one it already has.
///
/// Idempotent on purpose: provisioning deploys contracts after this, and a failed
/// deployment must retry against the same recovery address or the Safe it eventually
/// creates names an owner nobody holds.
pub async fn ensure_signer(
    pool: &PgPool,
    vault: &RecoveryVault,
    account_id: i64,
) -> Result<Address, AccountAuthError> {
    if let Some(existing) = signer_address(pool, account_id).await? {
        return Ok(existing);
    }

    let signer = PrivateKeySigner::random();
    let sealed = vault.seal(account_id, signer.to_bytes().as_slice())?;
    let address = format!("{:#x}", signer.address());

    sqlx::query(
        "INSERT INTO recovery_signers (account_id, address, key_id, sealed) VALUES ($1, $2, $3, $4) \
         ON CONFLICT (account_id) DO NOTHING",
    )
    .bind(account_id)
    .bind(&address)
    .bind(KEY_ID_ENV)
    .bind(&sealed)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("storing recovery signer: {error}")))?;

    // Two provisions racing insert once; both read back whatever landed.
    signer_address(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::Internal("recovery signer vanished after insert".into()))
}

pub async fn signer_address(pool: &PgPool, account_id: i64) -> Result<Option<Address>, AccountAuthError> {
    let row: Option<(String,)> =
        sqlx::query_as("SELECT address FROM recovery_signers WHERE account_id = $1")
            .bind(account_id)
            .fetch_optional(pool)
            .await
            .map_err(|error| AccountAuthError::Internal(format!("reading recovery signer: {error}")))?;
    row.map(|(address,)| {
        address
            .parse::<Address>()
            .map_err(|error| AccountAuthError::Internal(format!("stored recovery address is corrupt: {error}")))
    })
    .transpose()
}

/// Sign a Safe transaction hash with the account's Recovery Key.
///
/// The one place the key is unsealed. Callers are responsible for having checked that
/// the hash is an owner swap; this function does not know what it is signing, so the
/// policy lives next to the transaction builder, in `smart_accounts`.
pub async fn sign_safe_hash(
    pool: &PgPool,
    vault: &RecoveryVault,
    account_id: i64,
    hash: B256,
) -> Result<[u8; 65], AccountAuthError> {
    let row: Option<(Vec<u8>, String)> =
        sqlx::query_as("SELECT sealed, key_id FROM recovery_signers WHERE account_id = $1")
            .bind(account_id)
            .fetch_optional(pool)
            .await
            .map_err(|error| AccountAuthError::Internal(format!("reading recovery signer: {error}")))?;
    let (sealed, key_id) =
        row.ok_or_else(|| AccountAuthError::BadRequest("this account has no recovery key".into()))?;
    if key_id != KEY_ID_ENV {
        return Err(AccountAuthError::Internal(format!(
            "recovery key sealed under unknown key id {key_id}"
        )));
    }

    let secret = vault.open(account_id, &sealed)?;
    let secret: B256 = B256::try_from(secret.as_slice())
        .map_err(|_| AccountAuthError::Internal("unsealed recovery key has the wrong length".into()))?;
    let signer = PrivateKeySigner::from_bytes(&secret)
        .map_err(|error| AccountAuthError::Internal(format!("recovery key is not a valid key: {error}")))?;
    let signature = signer
        .sign_hash_sync(&hash)
        .map_err(|error| AccountAuthError::Internal(format!("signing with the recovery key: {error}")))?;
    Ok(signature.as_bytes())
}

// MARK: Email codes

/// Delivers recovery codes. Resend in production; a log line when RECOVERY_MAIL=log is
/// set for local work, which prints the code and is refused for anything else.
#[derive(Clone)]
pub enum Mailer {
    Resend {
        client: reqwest::Client,
        api_key: String,
        from: String,
    },
    Log,
}

impl Mailer {
    async fn send(&self, to: &str, subject: &str, text: &str, html: &str) -> Result<(), AccountAuthError> {
        match self {
            Mailer::Log => {
                tracing::warn!("RECOVERY_MAIL=log: mail to {to}: {subject}\n{text}");
                Ok(())
            }
            Mailer::Resend { client, api_key, from } => {
                let response = client
                    .post("https://api.resend.com/emails")
                    .bearer_auth(api_key)
                    .json(&serde_json::json!({
                        "from": from,
                        "to": [to],
                        "subject": subject,
                        "text": text,
                        "html": html,
                    }))
                    .send()
                    .await
                    .map_err(|error| AccountAuthError::Internal(format!("sending mail: {error}")))?;
                if !response.status().is_success() {
                    let status = response.status();
                    let body = response.text().await.unwrap_or_default();
                    // The body names the failure (bad from-domain, bad key); the code
                    // is not in it, so logging it is safe.
                    tracing::error!("resend refused the mail: {status} {body}");
                    return Err(AccountAuthError::Internal("the code could not be sent".into()));
                }
                Ok(())
            }
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct IssuedChallenge {
    pub expires_at: String,
    /// Where the code went, with enough hidden that the screen can show it safely.
    pub sent_to: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryGrant {
    pub grant_id: String,
    pub expires_at: String,
}

/// The email as a company sends one: the mark, the code large, what it does, and a
/// footer that says who sent it and where the policies are. A bare line of text from
/// an unknown sender reads as phishing, which is the last thing a recovery code can
/// afford to look like.
fn recovery_mail_html(code: &str, email: &str) -> String {
    let site = "https://recourse-arc.vercel.app";
    let to = escape_html(email);
    format!(
        r#"<!doctype html>
<html><body style="margin:0;padding:0;background:#f4f7f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#111b19;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f7f5;padding:32px 16px;">
<tr><td align="center">
<table role="presentation" width="520" cellspacing="0" cellpadding="0" style="max-width:520px;width:100%;background:#ffffff;border-radius:20px;border:1px solid #e3eae6;">
<tr><td style="padding:32px 36px 0 36px;">
  <table role="presentation" cellspacing="0" cellpadding="0"><tr>
    <td><img src="{site}/brand/recourse-mark.png" width="36" height="36" alt="Recourse" style="display:block;border-radius:9px;"></td>
    <td style="padding-left:12px;font-size:18px;font-weight:600;letter-spacing:-0.01em;">Recourse</td>
  </tr></table>
</td></tr>
<tr><td style="padding:36px 36px 0 36px;font-size:24px;font-weight:600;letter-spacing:-0.02em;">Your recovery code</td></tr>
<tr><td style="padding:12px 36px 0 36px;font-size:15px;line-height:1.55;color:#3a4441;">Enter this code in Recourse to move your account to this phone. It expires in 10 minutes.</td></tr>
<tr><td style="padding:24px 36px 0 36px;">
  <div style="background:#edf3ef;border-radius:14px;padding:22px;text-align:center;font-size:36px;font-weight:600;letter-spacing:0.28em;color:#075b46;font-variant-numeric:tabular-nums;">{code}</div>
</td></tr>
<tr><td style="padding:24px 36px 0 36px;font-size:14px;line-height:1.55;color:#66706d;">Recourse will never ask you for this code. If you did not ask for it, ignore this email: the code on its own cannot do anything. Moving your account also needs the key in your iCloud.</td></tr>
<tr><td style="padding:32px 36px 32px 36px;">
  <div style="border-top:1px solid #e3eae6;padding-top:20px;font-size:12px;line-height:1.6;color:#8a938f;">
    Sent to {to} because it is the recovery email on your Recourse account.<br>
    Recourse, the money app for dollars on your phone. USDC on Arc.<br>
    <a href="{site}/privacy" style="color:#075b46;text-decoration:none;">Privacy</a> &nbsp;·&nbsp;
    <a href="{site}/terms" style="color:#075b46;text-decoration:none;">Terms</a> &nbsp;·&nbsp;
    <a href="{site}/support" style="color:#075b46;text-decoration:none;">Support</a>
  </div>
</td></tr>
</table>
</td></tr>
</table>
</body></html>"#
    )
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

fn mask_email(email: &str) -> String {
    match email.split_once('@') {
        Some((user, domain)) => {
            let shown: String = user.chars().take(2).collect();
            format!("{shown}***@{domain}")
        }
        None => "***".into(),
    }
}

fn random_code() -> String {
    let n = OsRng.next_u32() % 10u32.pow(CODE_DIGITS);
    format!("{n:0width$}", width = CODE_DIGITS as usize)
}

fn hash_code(code: &str) -> Result<String, AccountAuthError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(code.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|error| AccountAuthError::Internal(format!("hashing the code: {error}")))
}

fn code_matches(code: &str, phc: &str) -> bool {
    PasswordHash::new(phc)
        .map(|parsed| Argon2::default().verify_password(code.as_bytes(), &parsed).is_ok())
        .unwrap_or(false)
}

/// Mail a fresh code for a purpose, retiring any code still open for it.
///
/// The address is the one on the account, never one from the request, so the only
/// inbox a code can ever reach is the one that already owns the account.
pub async fn issue_code(
    pool: &PgPool,
    mailer: &Mailer,
    account_id: i64,
    email: &str,
    purpose: &str,
) -> Result<IssuedChallenge, AccountAuthError> {
    let now = Utc::now();
    let recent: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM recovery_challenges WHERE account_id = $1 AND created_at > $2",
    )
    .bind(account_id)
    .bind(now - Duration::hours(1))
    .fetch_one(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("counting codes: {error}")))?;
    if recent >= MAX_CODES_PER_HOUR {
        return Err(AccountAuthError::Conflict(
            "too many codes were sent recently; wait a while and try again".into(),
        ));
    }

    // Two live codes would double the guessing surface under one attempt cap.
    sqlx::query(
        "UPDATE recovery_challenges SET expires_at = $3 \
         WHERE account_id = $1 AND purpose = $2 AND consumed_at IS NULL AND expires_at > $3",
    )
    .bind(account_id)
    .bind(purpose)
    .bind(now)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("retiring old codes: {error}")))?;

    let code = random_code();
    let expires_at = now + CODE_TTL;
    sqlx::query(
        "INSERT INTO recovery_challenges (account_id, purpose, code_hash, expires_at) VALUES ($1, $2, $3, $4)",
    )
    .bind(account_id)
    .bind(purpose)
    .bind(hash_code(&code)?)
    .bind(expires_at)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("storing the code: {error}")))?;

    mailer
        .send(
            email,
            "Your Recourse recovery code",
            &format!(
                "Your code is {code}. It expires in 10 minutes.\n\n\
                 Enter it in Recourse to move your account to this phone. If you did not ask for this, \
                 ignore this email: the code on its own cannot do anything."
            ),
            &recovery_mail_html(&code, email),
        )
        .await?;

    Ok(IssuedChallenge {
        expires_at: expires_at.to_rfc3339(),
        sent_to: mask_email(email),
    })
}

/// Check a code and hand back a grant the rotation spends.
///
/// The attempt is claimed in one statement so a burst of guesses costs one attempt
/// each rather than sharing the first.
pub async fn verify_code(
    pool: &PgPool,
    account_id: i64,
    purpose: &str,
    code: &str,
) -> Result<RecoveryGrant, AccountAuthError> {
    let now = Utc::now();
    let row: Option<(i64, String, i32)> = sqlx::query_as(
        "UPDATE recovery_challenges SET attempts = attempts + 1 \
         WHERE id = ( \
             SELECT id FROM recovery_challenges \
             WHERE account_id = $1 AND purpose = $2 AND consumed_at IS NULL AND verified_at IS NULL \
               AND expires_at > $3 AND attempts < $4 \
             ORDER BY created_at DESC LIMIT 1 \
         ) \
         RETURNING id, code_hash, attempts",
    )
    .bind(account_id)
    .bind(purpose)
    .bind(now)
    .bind(MAX_ATTEMPTS)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("claiming an attempt: {error}")))?;

    let (id, code_hash, _attempts) = row.ok_or_else(|| {
        AccountAuthError::BadRequest("no code is waiting; ask for a new one".into())
    })?;

    if !code_matches(code.trim(), &code_hash) {
        return Err(AccountAuthError::Unauthorized("that code is not right".into()));
    }

    let grant_id = crate::services::account_sessions::new_challenge_id();
    let grant_expires_at = now + GRANT_TTL;
    sqlx::query(
        "UPDATE recovery_challenges SET verified_at = $2, grant_id = $3, grant_expires_at = $4 WHERE id = $1",
    )
    .bind(id)
    .bind(now)
    .bind(&grant_id)
    .bind(grant_expires_at)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("recording the grant: {error}")))?;

    Ok(RecoveryGrant {
        grant_id,
        expires_at: grant_expires_at.to_rfc3339(),
    })
}

/// Confirm a grant is live for this account and purpose, without spending it.
pub async fn assert_grant(
    pool: &PgPool,
    account_id: i64,
    purpose: &str,
    grant_id: &str,
) -> Result<(), AccountAuthError> {
    let row: Option<(DateTime<Utc>,)> = sqlx::query_as(
        "SELECT grant_expires_at FROM recovery_challenges \
         WHERE account_id = $1 AND purpose = $2 AND grant_id = $3 AND consumed_at IS NULL",
    )
    .bind(account_id)
    .bind(purpose)
    .bind(grant_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading the grant: {error}")))?;
    match row {
        Some((expires,)) if expires > Utc::now() => Ok(()),
        Some(_) => Err(AccountAuthError::Unauthorized("that code has expired; ask for a new one".into())),
        None => Err(AccountAuthError::Unauthorized("no verified code for this request".into())),
    }
}

/// Spend a grant. Returns false if it was already spent or never existed.
pub async fn consume_grant(pool: &PgPool, account_id: i64, grant_id: &str) -> Result<bool, AccountAuthError> {
    let updated = sqlx::query(
        "UPDATE recovery_challenges SET consumed_at = now() \
         WHERE account_id = $1 AND grant_id = $2 AND consumed_at IS NULL AND grant_expires_at > now()",
    )
    .bind(account_id)
    .bind(grant_id)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("spending the grant: {error}")))?;
    Ok(updated.rows_affected() == 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn vault() -> RecoveryVault {
        RecoveryVault::from_base64(&base64::engine::general_purpose::STANDARD.encode([7u8; 32])).unwrap()
    }

    #[test]
    fn a_sealed_key_opens_for_its_own_account_only() {
        let vault = vault();
        let secret = [42u8; 32];
        let sealed = vault.seal(1, &secret).unwrap();
        assert_eq!(vault.open(1, &sealed).unwrap(), secret);
        assert!(vault.open(2, &sealed).is_err(), "a row moved to another account must not open");
    }

    #[test]
    fn sealing_twice_never_repeats_the_nonce() {
        let vault = vault();
        let a = vault.seal(1, &[1u8; 32]).unwrap();
        let b = vault.seal(1, &[1u8; 32]).unwrap();
        assert_ne!(a[..NONCE_BYTES], b[..NONCE_BYTES]);
    }

    #[test]
    fn the_wrapping_key_must_be_thirty_two_bytes() {
        assert!(RecoveryVault::from_base64("not base64!").is_err());
        assert!(RecoveryVault::from_base64(&base64::engine::general_purpose::STANDARD.encode([1u8; 16])).is_err());
    }

    #[test]
    fn codes_are_six_digits_and_hash_checks_round_trip() {
        let code = random_code();
        assert_eq!(code.len(), 6);
        assert!(code.chars().all(|c| c.is_ascii_digit()));
        let phc = hash_code(&code).unwrap();
        assert!(code_matches(&code, &phc));
        assert!(!code_matches("000000", &phc) || code == "000000");
    }

    #[test]
    fn masked_email_keeps_the_domain_and_two_letters() {
        assert_eq!(mask_email("frank@example.com"), "fr***@example.com");
        assert_eq!(mask_email("nonsense"), "***");
    }

    #[test]
    fn a_recovery_signature_recovers_to_the_key() {
        let signer = PrivateKeySigner::random();
        let hash = B256::repeat_byte(9);
        let signature = signer.sign_hash_sync(&hash).unwrap();
        let bytes = signature.as_bytes();
        assert!(bytes[64] == 27 || bytes[64] == 28, "Safe expects a plain ecrecover v");
        let recovered = alloy::primitives::Signature::try_from(&bytes[..])
            .unwrap()
            .recover_address_from_prehash(&hash)
            .unwrap();
        assert_eq!(recovered, signer.address());
    }
}
