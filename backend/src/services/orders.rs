use alloy::primitives::keccak256;
use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

use crate::services::evidence::normalize_hash;

// Content-addressed order store. A merchant's order manifest is an exact JSON document;
// its keccak256 over the raw bytes IS the bytes32 orderRef the escrow receives in pay().
// Storing the verbatim bytes keyed by that hash means the buyer can fetch the document,
// rehash it, and compare against the orderRef from the QR and the chain: no JSON
// canonicalization across Swift, Rust, and TypeScript, and no trusting mutable backend
// product details (a tampered manifest simply fails the hash check). Product images are
// stored the same way (blob keyed by keccak) and referenced from the manifest by hash.
#[derive(Clone)]
pub struct OrderStore {
    dir: PathBuf,
}

// The parsed shape of a v1 order manifest. Parsing is for validation and field access
// only; the stored artifact is always the client's exact bytes, never a re-serialization
// (re-serializing would change the hash and break the orderRef binding).
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct OrderManifest {
    pub version: u8,
    pub chain_id: u64,
    pub escrow: String,
    pub merchant: String,
    pub policy_id: u64,
    // USDC base units (6 decimals, R1) as a decimal string, exactly like the QR payload.
    pub amount: String,
    pub order_reference: String,
    pub item_name: String,
    pub description: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_content_type: Option<String>,
    pub created_at: i64,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredOrder {
    pub order_ref: String,
    pub size: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredImage {
    pub hash: String,
    pub size: usize,
    pub content_type: String,
}

pub struct ImageContent {
    pub bytes: Vec<u8>,
    pub content_type: String,
}

fn is_address(s: &str) -> bool {
    let h = s.strip_prefix("0x").unwrap_or("");
    h.len() == 40 && h.bytes().all(|b| b.is_ascii_hexdigit())
}

// Structural validation only; deployment checks (chainId, escrow) belong to the handler
// where AppConfig lives, so this stays reusable in tests without a config.
pub fn parse_manifest(bytes: &[u8]) -> Result<OrderManifest> {
    let manifest: OrderManifest = serde_json::from_slice(bytes).context("invalid manifest JSON")?;
    if manifest.version != 1 {
        return Err(anyhow!("unsupported manifest version {}", manifest.version));
    }
    if !is_address(&manifest.escrow) {
        return Err(anyhow!("invalid escrow address"));
    }
    if !is_address(&manifest.merchant) {
        return Err(anyhow!("invalid merchant address"));
    }
    if manifest.policy_id == 0 {
        return Err(anyhow!("policyId must be nonzero"));
    }
    let amount: u128 = manifest
        .amount
        .parse()
        .map_err(|_| anyhow!("amount must be a base-unit decimal string"))?;
    if amount == 0 {
        return Err(anyhow!("amount must be greater than zero"));
    }
    if manifest.item_name.trim().is_empty() {
        return Err(anyhow!("itemName is required"));
    }
    if manifest.description.trim().is_empty() {
        return Err(anyhow!("description is required"));
    }
    if manifest.order_reference.trim().is_empty() {
        return Err(anyhow!("orderReference is required"));
    }
    if let Some(hash) = &manifest.image_hash {
        if normalize_hash(hash).is_none() {
            return Err(anyhow!("imageHash must be a 32-byte hex hash"));
        }
    }
    Ok(manifest)
}

impl OrderStore {
    pub fn new(dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(dir.join("manifests")).context("creating order manifest dir")?;
        fs::create_dir_all(dir.join("images")).context("creating order image dir")?;
        Ok(Self { dir })
    }

    // Persist the exact manifest bytes under their keccak256. Identical bytes hash
    // identically, so a re-post of the same order is a no-op, not a conflict.
    pub fn put_manifest(&self, bytes: &[u8]) -> Result<StoredOrder> {
        let hex = format!("{:x}", keccak256(bytes));
        let path = self.dir.join("manifests").join(format!("{hex}.json"));
        if !path.exists() {
            fs::write(&path, bytes).context("writing order manifest")?;
        }
        Ok(StoredOrder {
            order_ref: format!("0x{hex}"),
            size: bytes.len(),
        })
    }

    pub fn get_manifest_bytes(&self, order_ref: &str) -> Result<Option<Vec<u8>>> {
        let hex = normalize_hash(order_ref).ok_or_else(|| anyhow!("invalid orderRef"))?;
        let path = self.dir.join("manifests").join(format!("{hex}.json"));
        match fs::read(&path) {
            Ok(bytes) => Ok(Some(bytes)),
            Err(_) => Ok(None),
        }
    }

    pub fn put_image(&self, bytes: &[u8], content_type: &str) -> Result<StoredImage> {
        let hex = format!("{:x}", keccak256(bytes));
        let blob_path = self.dir.join("images").join(&hex);
        let type_path = self.dir.join("images").join(format!("{hex}.type"));
        if !blob_path.exists() {
            fs::write(&blob_path, bytes).context("writing order image")?;
            fs::write(&type_path, content_type.as_bytes())
                .context("writing order image content-type")?;
        }
        Ok(StoredImage {
            hash: format!("0x{hex}"),
            size: bytes.len(),
            content_type: content_type.to_string(),
        })
    }

    pub fn get_image(&self, hash: &str) -> Result<Option<ImageContent>> {
        let hex = normalize_hash(hash).ok_or_else(|| anyhow!("invalid image hash"))?;
        let blob_path = self.dir.join("images").join(&hex);
        if !blob_path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&blob_path).context("reading order image")?;
        let content_type = fs::read_to_string(self.dir.join("images").join(format!("{hex}.type")))
            .unwrap_or_else(|_| "application/octet-stream".to_string());
        Ok(Some(ImageContent {
            bytes,
            content_type,
        }))
    }

    pub fn has_image(&self, hash: &str) -> bool {
        normalize_hash(hash)
            .map(|hex| self.dir.join("images").join(hex).exists())
            .unwrap_or(false)
    }

    // A .cdn sidecar records where the image also lives on Cloudinary. Content
    // addressing makes that copy immutable, so a recorded URL never goes stale.
    pub fn set_cdn_url(&self, hash: &str, url: &str) -> Result<()> {
        let hex = normalize_hash(hash).ok_or_else(|| anyhow!("invalid image hash"))?;
        fs::write(
            self.dir.join("images").join(format!("{hex}.cdn")),
            url.as_bytes(),
        )
        .context("writing image cdn sidecar")
    }

    pub fn cdn_url(&self, hash: &str) -> Option<String> {
        let hex = normalize_hash(hash)?;
        fs::read_to_string(self.dir.join("images").join(format!("{hex}.cdn")))
            .ok()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The cross-language golden fixture: Swift and TypeScript hash these exact bytes and
    // must produce the same orderRef. If this changes, update OrderManifestTests.swift
    // and the engine test in the same commit.
    const FIXTURE: &str = "{\"version\":1,\"chainId\":5042002,\"escrow\":\"0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0\",\"merchant\":\"0xD6c574461d96Ee708f58Fe553049aD4f48BB983A\",\"policyId\":1,\"amount\":\"250000\",\"orderReference\":\"ORDER-1001\",\"itemName\":\"API Credits Pack\",\"description\":\"1,000 cloud compute credits\",\"createdAt\":1784900000}";

    // One directory per call: tests run in parallel in one process, and a shared
    // directory that each test wipes on entry races with the others.
    fn store() -> OrderStore {
        static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("recourse-orders-test-{}-{n}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        OrderStore::new(dir).unwrap()
    }

    // Computed with viem keccak256 over the same bytes, so Rust and TypeScript provably
    // agree; OrderManifestTests.swift asserts the identical value from Swift.
    const GOLDEN_ORDER_REF: &str =
        "0xa4e970942b2f79b3ef97bd7cbb6a64dd5c92ce63e6c6facc758792f69a88b7cd";

    #[test]
    fn manifest_roundtrips_by_its_hash() {
        let store = store();
        let stored = store.put_manifest(FIXTURE.as_bytes()).unwrap();
        assert_eq!(stored.order_ref, GOLDEN_ORDER_REF);
        assert_eq!(
            stored.order_ref,
            format!("0x{:x}", keccak256(FIXTURE.as_bytes()))
        );
        let bytes = store
            .get_manifest_bytes(&stored.order_ref)
            .unwrap()
            .unwrap();
        // Verbatim bytes: the fetched document rehashes to its own key.
        assert_eq!(bytes, FIXTURE.as_bytes());
        assert_eq!(format!("0x{:x}", keccak256(&bytes)), stored.order_ref);
        assert!(store.get_manifest_bytes("0xdead").is_err());
    }

    #[test]
    fn fixture_parses_and_validates() {
        let m = parse_manifest(FIXTURE.as_bytes()).unwrap();
        assert_eq!(m.chain_id, 5042002);
        assert_eq!(m.policy_id, 1);
        assert_eq!(m.amount, "250000");
        assert_eq!(m.item_name, "API Credits Pack");
        assert!(m.image_hash.is_none());
    }

    #[test]
    fn structural_validation_rejects_bad_manifests() {
        let reject = |json: &str| assert!(parse_manifest(json.as_bytes()).is_err(), "{json}");
        reject("not json");
        // Wrong version.
        reject(&FIXTURE.replace("\"version\":1", "\"version\":2"));
        // Empty item name.
        reject(&FIXTURE.replace("API Credits Pack", ""));
        // Zero amount.
        reject(&FIXTURE.replace("\"250000\"", "\"0\""));
        // Amount not base units.
        reject(&FIXTURE.replace("\"250000\"", "\"0.25\""));
        // Malformed merchant address.
        reject(&FIXTURE.replace("0xD6c574461d96Ee708f58Fe553049aD4f48BB983A", "0x1234"));
        // Malformed image hash.
        let with_bad_image =
            FIXTURE.replace("\"createdAt\"", "\"imageHash\":\"0xzz\",\"createdAt\"");
        reject(&with_bad_image);
    }

    #[test]
    fn image_roundtrips_content_addressed() {
        let store = store();
        let stored = store.put_image(b"fake-jpeg-bytes", "image/jpeg").unwrap();
        assert_eq!(
            stored.hash,
            format!("0x{:x}", keccak256(b"fake-jpeg-bytes"))
        );
        assert!(store.has_image(&stored.hash));
        let got = store.get_image(&stored.hash).unwrap().unwrap();
        assert_eq!(got.bytes, b"fake-jpeg-bytes");
        assert_eq!(got.content_type, "image/jpeg");
        assert!(
            !store.has_image("0x0000000000000000000000000000000000000000000000000000000000000001")
        );
    }
}
