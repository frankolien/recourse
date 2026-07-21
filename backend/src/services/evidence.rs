use alloy::primitives::{keccak256, B256};
use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;

// Content-addressed evidence blob store. A blob's id is its keccak256 hash, which is
// exactly the value that goes on-chain as EvidenceItem.hash in fileDispute, so the
// escrow's evidenceRoot commits to precisely what this store holds and anyone can
// re-verify a blob by rehashing it. Evidence is real user data, kept on the filesystem
// and out of the disposable indexer projection (which gets truncated on redeploy).
#[derive(Clone)]
pub struct EvidenceStore {
    dir: PathBuf,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StoredBlob {
    pub hash: String,
    pub size: usize,
    pub content_type: String,
}

pub struct BlobContent {
    pub bytes: Vec<u8>,
    pub content_type: String,
}

// One evidence item as the buyer pinned it on-chain in fileDispute: an evType bit
// (PHOTO 1, DESCRIPTION 2, TRACKING_REF 4, VIDEO 8) and the keccak256 of the blob.
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct ManifestItem {
    pub ev_type: u8,
    pub hash: String,
}

// The ordered evidence list for a payment. The escrow only stores the folded root
// (evidence items are calldata, never state), so the list itself lives off-chain here,
// but it is only ever persisted after its fold is checked against the onchain root.
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EvidenceManifest {
    pub payment_id: i64,
    pub evidence_root: String,
    pub items: Vec<ManifestItem>,
}

// Reproduces RecourseEscrow.fileDispute byte-for-byte:
//   root = 0; for each item: root = keccak256(abi.encodePacked(root, evType, hash))
// abi.encodePacked means no padding: root is 32 bytes, evType 1 byte, hash 32 bytes,
// so each preimage is exactly 65 bytes. Empty list folds to bytes32(0). Order matters.
pub fn compute_evidence_root(items: &[ManifestItem]) -> Result<B256> {
    let mut root = B256::ZERO;
    for item in items {
        let hash = parse_b256(&item.hash)?;
        let mut buf = [0u8; 65];
        buf[..32].copy_from_slice(root.as_slice());
        buf[32] = item.ev_type;
        buf[33..].copy_from_slice(hash.as_slice());
        root = keccak256(buf);
    }
    Ok(root)
}

fn parse_b256(s: &str) -> Result<B256> {
    let h = normalize_hash(s).ok_or_else(|| anyhow!("invalid hash: {s}"))?;
    B256::from_str(&h).map_err(|e| anyhow!("invalid hash {s}: {e}"))
}

// Accepts a 32-byte hex hash with or without 0x; also guards path traversal since the
// hash becomes a filename.
fn normalize_hash(s: &str) -> Option<String> {
    let h = s.strip_prefix("0x").unwrap_or(s);
    if h.len() == 64 && h.bytes().all(|b| b.is_ascii_hexdigit()) {
        Some(h.to_lowercase())
    } else {
        None
    }
}

impl EvidenceStore {
    pub fn new(dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&dir).with_context(|| format!("creating evidence dir {}", dir.display()))?;
        Ok(Self { dir })
    }

    pub fn put(&self, bytes: &[u8], content_type: &str) -> Result<StoredBlob> {
        let hex = format!("{:x}", keccak256(bytes)); // 64 chars, no 0x prefix
        let blob_path = self.dir.join(&hex);
        let type_path = self.dir.join(format!("{hex}.type"));
        // Content-addressed: identical bytes hash identically, so an existing blob is
        // already the same data; skip the rewrite.
        if !blob_path.exists() {
            fs::write(&blob_path, bytes).context("writing evidence blob")?;
            fs::write(&type_path, content_type.as_bytes()).context("writing evidence content-type")?;
        }
        Ok(StoredBlob {
            hash: format!("0x{hex}"),
            size: bytes.len(),
            content_type: content_type.to_string(),
        })
    }

    pub fn get(&self, hash: &str) -> Result<Option<BlobContent>> {
        let hex = normalize_hash(hash).ok_or_else(|| anyhow!("invalid evidence hash"))?;
        let blob_path = self.dir.join(&hex);
        if !blob_path.exists() {
            return Ok(None);
        }
        let bytes = fs::read(&blob_path).context("reading evidence blob")?;
        let content_type = fs::read_to_string(self.dir.join(format!("{hex}.type")))
            .unwrap_or_else(|_| "application/octet-stream".to_string());
        Ok(Some(BlobContent { bytes, content_type }))
    }

    // Size and content-type of a stored blob without reading it into memory; used to
    // report per-item availability in a payment's evidence view. None if not held.
    pub fn stat(&self, hash: &str) -> Result<Option<(usize, String)>> {
        let hex = normalize_hash(hash).ok_or_else(|| anyhow!("invalid evidence hash"))?;
        match fs::metadata(self.dir.join(&hex)) {
            Ok(m) => {
                let content_type = fs::read_to_string(self.dir.join(format!("{hex}.type")))
                    .unwrap_or_else(|_| "application/octet-stream".to_string());
                Ok(Some((m.len() as usize, content_type)))
            }
            Err(_) => Ok(None),
        }
    }

    // Manifests are scoped by deployment (chainId + escrow) because paymentIds are only
    // unique within one deployment; a redeploy reuses id 1, 2, ... for different payments.
    // Blobs need no such scoping since they are addressed by their content hash.
    pub fn put_manifest(&self, deployment: &str, manifest: &EvidenceManifest) -> Result<()> {
        let dir = self.dir.join("manifests").join(deployment);
        fs::create_dir_all(&dir).context("creating manifest dir")?;
        let path = dir.join(format!("{}.json", manifest.payment_id));
        let json = serde_json::to_vec_pretty(manifest).context("serializing manifest")?;
        fs::write(&path, json).context("writing manifest")?;
        Ok(())
    }

    pub fn get_manifest(&self, deployment: &str, payment_id: i64) -> Result<Option<EvidenceManifest>> {
        let path = self.dir.join("manifests").join(deployment).join(format!("{payment_id}.json"));
        match fs::read(&path) {
            Ok(bytes) => Ok(Some(serde_json::from_slice(&bytes).context("parsing manifest")?)),
            Err(_) => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_is_keccak256() {
        // Well-known vector: keccak256("hello").
        assert_eq!(
            format!("{:x}", keccak256(b"hello")),
            "1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
        );
    }

    #[test]
    fn put_then_get_roundtrips() {
        let dir = std::env::temp_dir().join("recourse-evidence-test");
        let store = EvidenceStore::new(dir).unwrap();
        let stored = store.put(b"hello", "text/plain").unwrap();
        assert_eq!(stored.hash, "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8");
        let got = store.get(&stored.hash).unwrap().unwrap();
        assert_eq!(got.bytes, b"hello");
        assert_eq!(got.content_type, "text/plain");
        assert!(store.get("0xdeadbeef").is_err()); // malformed hash rejected
    }

    // Golden vectors cross-checked with `cast keccak` against the escrow's
    // abi.encodePacked(root, evType, hash) fold. If this drifts, evidence proofs break.
    const PHOTO: &str = "0x6c910f9470010ccea7fc0236c4e46ee4dda1dc89348fefefef37f36759f0dc0f";
    const DESC: &str = "0x1596dc38e2ac5a6ddc5e019af4adcc1e017a04f510d57e69d6879d5d2996bb8e";

    fn item(ev_type: u8, hash: &str) -> ManifestItem {
        ManifestItem { ev_type, hash: hash.to_string() }
    }

    #[test]
    fn evidence_root_matches_onchain_fold() {
        // Empty fold is bytes32(0), exactly like fileDispute with no evidence.
        assert_eq!(compute_evidence_root(&[]).unwrap(), B256::ZERO);

        let one = compute_evidence_root(&[item(1, PHOTO)]).unwrap();
        assert_eq!(format!("{one:#x}"), "0xd0238185653e5f9582007ef867b8d6351dd4084a0934519138979055ba0917f8");

        let two = compute_evidence_root(&[item(1, PHOTO), item(2, DESC)]).unwrap();
        assert_eq!(format!("{two:#x}"), "0x2a4a7bdcd693631dbb90c86f4470068e26e0e4be090bb1412523fe0f9263ccd4");

        // The fold is order-sensitive, so swapping the two items changes the root.
        let swapped = compute_evidence_root(&[item(2, DESC), item(1, PHOTO)]).unwrap();
        assert_ne!(swapped, two);
    }

    #[test]
    fn manifest_put_then_get_roundtrips() {
        let dir = std::env::temp_dir().join("recourse-manifest-test");
        let _ = fs::remove_dir_all(&dir);
        let store = EvidenceStore::new(dir).unwrap();
        let deployment = "5042002_0x00000000000000000000000000000000000000ab";
        let manifest = EvidenceManifest {
            payment_id: 42,
            evidence_root: "0xd0238185653e5f9582007ef867b8d6351dd4084a0934519138979055ba0917f8".to_string(),
            items: vec![item(1, PHOTO)],
        };
        store.put_manifest(deployment, &manifest).unwrap();
        let got = store.get_manifest(deployment, 42).unwrap().unwrap();
        assert_eq!(got.payment_id, 42);
        assert_eq!(got.items.len(), 1);
        assert_eq!(got.items[0].ev_type, 1);
        assert!(store.get_manifest(deployment, 999).unwrap().is_none());
    }
}
