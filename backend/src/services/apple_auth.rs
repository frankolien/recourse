use anyhow::{bail, Context, Result};
use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{
    decode, decode_header, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation,
};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

use crate::services::AppConfig;

const APPLE_ISSUER: &str = "https://appleid.apple.com";
const APPLE_TOKEN_URL: &str = "https://appleid.apple.com/auth/token";
const APPLE_KEYS_URL: &str = "https://appleid.apple.com/auth/keys";
const CLIENT_SECRET_TTL_SECS: u64 = 300;

#[derive(Clone)]
pub struct AppleAuthService {
    client: Client,
    team_id: String,
    key_id: String,
    client_id: String,
    signing_key: Arc<EncodingKey>,
    cached_keys: Arc<RwLock<Option<JwkSet>>>,
}

#[derive(Debug, Clone)]
pub struct VerifiedAppleIdentity {
    pub subject: String,
    pub email: Option<String>,
}

#[derive(Debug, Serialize)]
struct ClientSecretClaims<'a> {
    iss: &'a str,
    iat: u64,
    exp: u64,
    aud: &'static str,
    sub: &'a str,
}

#[derive(Debug, Deserialize)]
struct AppleTokenResponse {
    id_token: Option<String>,
    error: Option<String>,
    error_description: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AppleIdentityClaims {
    iss: String,
    aud: String,
    exp: u64,
    sub: String,
    nonce: Option<String>,
    email: Option<String>,
}

impl AppleAuthService {
    pub fn from_config(config: &AppConfig) -> Result<Option<Self>> {
        let identifiers = (
            config.apple_team_id.as_deref(),
            config.apple_key_id.as_deref(),
            config.apple_client_id.as_deref(),
        );
        let has_key =
            config.apple_private_key_path.is_some() || config.apple_private_key_p8.is_some();

        let (team_id, key_id, client_id) = match identifiers {
            (None, None, None) if !has_key => return Ok(None),
            (Some(team_id), Some(key_id), Some(client_id)) if has_key => {
                (team_id, key_id, client_id)
            }
            _ => bail!("Sign in with Apple is partially configured; set all APPLE_* variables"),
        };

        let private_key = match (
            config.apple_private_key_path.as_ref(),
            config.apple_private_key_p8.as_deref(),
        ) {
            (Some(_), Some(_)) => {
                bail!("set only one of APPLE_PRIVATE_KEY_PATH or APPLE_PRIVATE_KEY_P8")
            }
            (Some(key_path), None) => std::fs::read(key_path)
                .with_context(|| format!("reading Apple private key at {}", key_path.display()))?,
            (None, Some(value)) => value.replace("\\n", "\n").into_bytes(),
            (None, None) => unreachable!("Apple key presence checked above"),
        };

        Self::new(team_id, key_id, client_id, &private_key).map(Some)
    }

    fn new(team_id: &str, key_id: &str, client_id: &str, private_key: &[u8]) -> Result<Self> {
        let signing_key =
            EncodingKey::from_ec_pem(private_key).context("parsing Apple Sign in private key")?;

        Ok(Self {
            client: Client::builder()
                .https_only(true)
                .build()
                .context("building Apple auth HTTP client")?,
            team_id: team_id.to_string(),
            key_id: key_id.to_string(),
            client_id: client_id.to_string(),
            signing_key: Arc::new(signing_key),
            cached_keys: Arc::new(RwLock::new(None)),
        })
    }

    pub async fn exchange_code(
        &self,
        authorization_code: &str,
        expected_nonce_hash: &str,
    ) -> Result<VerifiedAppleIdentity> {
        let client_secret = self.client_secret()?;
        let response = self
            .client
            .post(APPLE_TOKEN_URL)
            .form(&[
                ("client_id", self.client_id.as_str()),
                ("client_secret", client_secret.as_str()),
                ("code", authorization_code),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .context("calling Apple token endpoint")?;
        let status = response.status();
        let payload: AppleTokenResponse = response
            .json()
            .await
            .context("decoding Apple token response")?;

        if !status.is_success() {
            bail!(
                "Apple token exchange rejected: {}{}",
                payload.error.unwrap_or_else(|| status.to_string()),
                payload
                    .error_description
                    .map(|description| format!(" ({description})"))
                    .unwrap_or_default()
            );
        }

        let identity_token = payload
            .id_token
            .context("Apple response omitted id_token")?;
        self.verify_identity_token(&identity_token, expected_nonce_hash)
            .await
    }

    fn client_secret(&self) -> Result<String> {
        let now = now_secs();
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let claims = ClientSecretClaims {
            iss: &self.team_id,
            iat: now,
            exp: now + CLIENT_SECRET_TTL_SECS,
            aud: APPLE_ISSUER,
            sub: &self.client_id,
        };
        encode(&header, &claims, &self.signing_key).context("creating Apple client secret")
    }

    async fn verify_identity_token(
        &self,
        token: &str,
        expected_nonce_hash: &str,
    ) -> Result<VerifiedAppleIdentity> {
        let header = decode_header(token).context("reading Apple identity-token header")?;
        if header.alg != Algorithm::RS256 {
            bail!("Apple identity token used an unexpected algorithm");
        }
        let key_id = header.kid.context("Apple identity token omitted kid")?;
        let decoding_key = self.decoding_key(&key_id).await?;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&[APPLE_ISSUER]);
        validation.set_audience(&[self.client_id.as_str()]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.leeway = 30;

        let token_data = decode::<AppleIdentityClaims>(token, &decoding_key, &validation)
            .context("verifying Apple identity token")?;
        let claims = token_data.claims;
        if claims.iss != APPLE_ISSUER || claims.aud != self.client_id || claims.exp <= now_secs() {
            bail!("Apple identity-token claims are invalid");
        }
        if claims.nonce.as_deref() != Some(expected_nonce_hash) {
            bail!("Apple identity-token nonce mismatch");
        }

        Ok(VerifiedAppleIdentity {
            subject: claims.sub,
            email: claims.email,
        })
    }

    async fn decoding_key(&self, key_id: &str) -> Result<DecodingKey> {
        if let Some(key) = self.find_cached_key(key_id).await? {
            return Ok(key);
        }

        let keys: JwkSet = self
            .client
            .get(APPLE_KEYS_URL)
            .send()
            .await
            .context("fetching Apple signing keys")?
            .error_for_status()
            .context("Apple signing-key request failed")?
            .json()
            .await
            .context("decoding Apple signing keys")?;
        let key = keys
            .find(key_id)
            .context("Apple signing key was not found")?;
        let decoding_key = DecodingKey::from_jwk(key).context("reading Apple signing key")?;
        *self.cached_keys.write().await = Some(keys);
        Ok(decoding_key)
    }

    async fn find_cached_key(&self, key_id: &str) -> Result<Option<DecodingKey>> {
        let keys = self.cached_keys.read().await;
        let Some(keys) = keys.as_ref() else {
            return Ok(None);
        };
        keys.find(key_id)
            .map(DecodingKey::from_jwk)
            .transpose()
            .context("reading cached Apple signing key")
    }
}

pub fn sha256_hex(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nonce_hash_matches_sha256_vector() {
        assert_eq!(
            sha256_hex("recourse"),
            "df9a13af0ade07707ff6e32583149e1ea18657d2ee020302baa1c1a021aeae1d"
        );
    }
}
