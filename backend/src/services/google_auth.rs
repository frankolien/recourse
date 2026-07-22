use anyhow::{bail, Context, Result};
use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use reqwest::Client;
use serde::Deserialize;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

use crate::services::AppConfig;

const GOOGLE_ISSUERS: [&str; 2] = ["https://accounts.google.com", "accounts.google.com"];
const GOOGLE_KEYS_URL: &str = "https://www.googleapis.com/oauth2/v3/certs";

// Verifies the ID token that Google Identity Services hands the web client. There is no
// server nonce here (unlike Apple): the ID token is freshly minted per sign-in, RS256
// signed by Google, bound to our OAuth client id (aud), and short lived, which is the
// standard Google verification. It only proves identity; Arc wallet signatures still
// authorize payment writes.
#[derive(Clone)]
pub struct GoogleAuthService {
    client: Client,
    client_id: String,
    cached_keys: Arc<RwLock<Option<JwkSet>>>,
}

#[derive(Debug, Clone)]
pub struct VerifiedGoogleIdentity {
    pub subject: String,
    pub email: Option<String>,
    pub given_name: Option<String>,
    pub family_name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GoogleIdentityClaims {
    iss: String,
    aud: String,
    exp: u64,
    sub: String,
    email: Option<String>,
    given_name: Option<String>,
    family_name: Option<String>,
}

impl GoogleAuthService {
    pub fn from_config(config: &AppConfig) -> Result<Option<Self>> {
        match config.google_client_id.as_deref() {
            Some(client_id) => Self::new(client_id).map(Some),
            None => Ok(None),
        }
    }

    fn new(client_id: &str) -> Result<Self> {
        Ok(Self {
            client: Client::builder()
                .https_only(true)
                .build()
                .context("building Google auth HTTP client")?,
            client_id: client_id.to_string(),
            cached_keys: Arc::new(RwLock::new(None)),
        })
    }

    pub async fn verify_id_token(&self, token: &str) -> Result<VerifiedGoogleIdentity> {
        let header = decode_header(token).context("reading Google identity-token header")?;
        if header.alg != Algorithm::RS256 {
            bail!("Google identity token used an unexpected algorithm");
        }
        let key_id = header.kid.context("Google identity token omitted kid")?;
        let decoding_key = self.decoding_key(&key_id).await?;
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&GOOGLE_ISSUERS);
        validation.set_audience(&[self.client_id.as_str()]);
        validation.set_required_spec_claims(&["exp", "iss", "aud", "sub"]);
        validation.leeway = 30;

        let token_data = decode::<GoogleIdentityClaims>(token, &decoding_key, &validation)
            .context("verifying Google identity token")?;
        let claims = token_data.claims;
        if !GOOGLE_ISSUERS.contains(&claims.iss.as_str())
            || claims.aud != self.client_id
            || claims.exp <= now_secs()
        {
            bail!("Google identity-token claims are invalid");
        }

        Ok(VerifiedGoogleIdentity {
            subject: claims.sub,
            email: claims.email,
            given_name: claims.given_name,
            family_name: claims.family_name,
        })
    }

    async fn decoding_key(&self, key_id: &str) -> Result<DecodingKey> {
        if let Some(key) = self.find_cached_key(key_id).await? {
            return Ok(key);
        }
        let keys: JwkSet = self
            .client
            .get(GOOGLE_KEYS_URL)
            .send()
            .await
            .context("fetching Google signing keys")?
            .error_for_status()
            .context("Google signing-key request failed")?
            .json()
            .await
            .context("decoding Google signing keys")?;
        let key = keys
            .find(key_id)
            .context("Google signing key was not found")?;
        let decoding_key = DecodingKey::from_jwk(key).context("reading Google signing key")?;
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
            .context("reading cached Google signing key")
    }
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

    #[tokio::test]
    async fn rejects_non_jwt() {
        let service = GoogleAuthService::new("test.apps.googleusercontent.com").unwrap();
        assert!(service.verify_id_token("not-a-jwt").await.is_err());
    }
}
