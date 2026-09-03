use anyhow::{anyhow, Context, Result};
use base64::Engine;
use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

// Off-box home for product images. The volume store stays the source of truth the
// instant an upload lands; Cloudinary adds durability across volume loss and CDN
// delivery for buyers. Integrity is unaffected: images are content-addressed and the
// buyer rehashes whatever bytes it receives, and Cloudinary returns the original bytes
// unchanged when the asset is fetched without transformation parameters.
#[derive(Clone)]
pub struct Cloudinary {
    cloud_name: String,
    api_key: String,
    api_secret: String,
    http: reqwest::Client,
}

#[derive(Deserialize)]
struct UploadResponse {
    secure_url: String,
}

impl Cloudinary {
    // Standard single-var config: cloudinary://<api_key>:<api_secret>@<cloud_name>.
    // Absent or malformed means the feature is off and images stay volume-only, so a
    // missing credential can never take image upload down.
    pub fn from_env() -> Option<Self> {
        let url = std::env::var("CLOUDINARY_URL").ok()?;
        match Self::parse(&url) {
            Ok(client) => Some(client),
            Err(e) => {
                tracing::warn!("CLOUDINARY_URL ignored: {e}");
                None
            }
        }
    }

    fn parse(url: &str) -> Result<Self> {
        let rest = url
            .strip_prefix("cloudinary://")
            .ok_or_else(|| anyhow!("must start with cloudinary://"))?;
        let (credentials, cloud_name) = rest
            .split_once('@')
            .ok_or_else(|| anyhow!("missing @cloud_name"))?;
        let (api_key, api_secret) = credentials
            .split_once(':')
            .ok_or_else(|| anyhow!("missing api_key:api_secret"))?;
        if api_key.is_empty() || api_secret.is_empty() || cloud_name.is_empty() {
            return Err(anyhow!(
                "api_key, api_secret, and cloud_name are all required"
            ));
        }
        Ok(Self {
            cloud_name: cloud_name.to_string(),
            api_key: api_key.to_string(),
            api_secret: api_secret.to_string(),
            http: reqwest::Client::new(),
        })
    }

    /// Upload image bytes under a public_id derived from their keccak hex. Re-uploading
    /// the same hash overwrites the same asset with identical bytes, so the call is
    /// idempotent. Returns the delivery URL for the stored original.
    pub async fn upload(&self, hex_hash: &str, bytes: &[u8], content_type: &str) -> Result<String> {
        let public_id = format!("recourse/orders/{hex_hash}");
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .context("system clock before epoch")?
            .as_secs()
            .to_string();
        // Signature covers the sorted non-file params plus the secret. Cloudinary
        // detects SHA-256 by signature length, which lets us reuse the sha2 dependency
        // instead of adding a SHA-1 crate.
        let signature = Self::signature(&public_id, &timestamp, &self.api_secret);
        let file = format!(
            "data:{content_type};base64,{}",
            base64::engine::general_purpose::STANDARD.encode(bytes)
        );
        let endpoint = format!(
            "https://api.cloudinary.com/v1_1/{}/image/upload",
            self.cloud_name
        );
        let form = [
            ("file", file),
            ("public_id", public_id),
            ("timestamp", timestamp),
            ("api_key", self.api_key.clone()),
            ("signature", signature),
        ];
        let response = self
            .http
            .post(&endpoint)
            .form(&form)
            .send()
            .await
            .context("cloudinary upload request")?;
        let status = response.status();
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(anyhow!("cloudinary upload failed ({status}): {body}"));
        }
        let parsed: UploadResponse = response
            .json()
            .await
            .context("cloudinary upload response")?;
        Ok(parsed.secure_url)
    }

    fn signature(public_id: &str, timestamp: &str, api_secret: &str) -> String {
        let to_sign = format!("public_id={public_id}&timestamp={timestamp}{api_secret}");
        format!("{:x}", Sha256::digest(to_sign.as_bytes()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_cloudinary_url() {
        let c = Cloudinary::parse("cloudinary://123456789:abcSECRET@demo-cloud").unwrap();
        assert_eq!(c.cloud_name, "demo-cloud");
        assert_eq!(c.api_key, "123456789");
        assert_eq!(c.api_secret, "abcSECRET");
    }

    #[test]
    fn rejects_malformed_urls() {
        assert!(Cloudinary::parse("https://x:y@z").is_err());
        assert!(Cloudinary::parse("cloudinary://missing-at").is_err());
        assert!(Cloudinary::parse("cloudinary://nokey@cloud").is_err());
        assert!(Cloudinary::parse("cloudinary://:nosecret@cloud").is_err());
        assert!(Cloudinary::parse("cloudinary://k:s@").is_err());
    }

    #[test]
    fn signature_is_sha256_over_sorted_params_plus_secret() {
        // Deterministic vector so a refactor cannot silently change what gets signed.
        let got = Cloudinary::signature("recourse/orders/abc", "1700000000", "shhh");
        let want = format!(
            "{:x}",
            Sha256::digest(b"public_id=recourse/orders/abc&timestamp=1700000000shhh")
        );
        assert_eq!(got, want);
    }
}
