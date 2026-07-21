use alloy::primitives::keccak256;
use anyhow::{anyhow, Context, Result};
use serde::Serialize;
use std::fs;
use std::path::PathBuf;

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
}
