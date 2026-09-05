//! What the backend does on-chain for an account's Safe: deploys the Device Key's
//! owner contract and the Safe itself at enrolment, and relays an owner swap at
//! recovery. It pays gas for all three from the attestor key. It holds no owner key
//! and cannot make the Safe do anything its owners did not sign.

use alloy::network::EthereumWallet;
use alloy::primitives::{Address, Bytes, B256, U256};
use alloy::providers::fillers::{ChainIdFiller, GasFiller, NonceFiller, SimpleNonceManager};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};

use crate::services::olien::retry_nonce;
use alloy::signers::local::PrivateKeySigner;
use alloy::sol;
use alloy::sol_types::SolCall;
use anyhow::{anyhow, Context, Result};
use serde::Deserialize;

sol! {
    #[sol(rpc)]
    interface IP256OwnerFactory {
        function create(uint256 x, uint256 y) external returns (address owner);
        function getAddress(uint256 x, uint256 y) external view returns (address);
    }

    #[sol(rpc)]
    interface ISafeProxyFactory {
        function createProxyWithNonce(address _singleton, bytes memory initializer, uint256 saltNonce) external returns (address proxy);
    }

    #[sol(rpc)]
    interface ISafe {
        function setup(address[] _owners, uint256 _threshold, address to, bytes data, address fallbackHandler, address paymentToken, uint256 payment, address paymentReceiver) external;
        function getOwners() external view returns (address[]);
        function getThreshold() external view returns (uint256);
        function nonce() external view returns (uint256);
        function isModuleEnabled(address module) external view returns (bool);
        function getTransactionHash(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, uint256 _nonce) external view returns (bytes32);
        function execTransaction(address to, uint256 value, bytes data, uint8 operation, uint256 safeTxGas, uint256 baseGas, uint256 gasPrice, address gasToken, address refundReceiver, bytes signatures) external payable returns (bool success);
        function swapOwner(address prevOwner, address oldOwner, address newOwner) external;
    }

    interface ISafeModuleSetup {
        function enableModules(address[] modules) external;
    }
}

/// The Safe's owner linked list starts at this sentinel; swapping the first owner
/// names it as the predecessor.
pub const SENTINEL_OWNER: Address = Address::with_last_byte(1);

/// Canonical Safe 1.4.1 and 4337 module addresses, read from the deployment file so
/// nothing here is hardcoded.
#[derive(Debug, Clone, Deserialize)]
pub struct SafeDeployment {
    pub singleton: Address,
    #[serde(rename = "proxyFactory")]
    pub proxy_factory: Address,
    #[serde(rename = "moduleSetup")]
    pub module_setup: Address,
    #[serde(rename = "module4337")]
    pub module_4337: Address,
    #[serde(rename = "entryPoint")]
    pub entry_point: Address,
}

#[derive(Clone)]
pub struct SafeClient {
    provider: DynProvider,
    safe: SafeDeployment,
    p256_owner_factory: Address,
}

pub struct Deployed {
    pub address: Address,
    pub tx_hash: B256,
}

/// One owner's 65-byte signature, ready to be packed in Safe order.
pub struct OwnerSignature {
    pub owner: Address,
    pub signature: [u8; 65],
}

impl SafeClient {
    pub fn new(
        rpc_url: &str,
        private_key: &str,
        safe: SafeDeployment,
        p256_owner_factory: Address,
    ) -> Result<Self> {
        let signer: PrivateKeySigner = private_key.trim().parse().context("parsing the deployer key")?;
        let url = rpc_url.parse().context("parsing RPC URL for the Safe client")?;
        // The deployer key is shared with the Olien relayer and with scripts, so the
        // nonce is read from the node at every send rather than cached: a cached nonce
        // goes stale the moment another process spends from the same key.
        let provider = ProviderBuilder::new()
            .disable_recommended_fillers()
            .filler(GasFiller)
            .filler(ChainIdFiller::default())
            .filler(NonceFiller::new(SimpleNonceManager::default()))
            .wallet(EthereumWallet::from(signer))
            .connect_http(url)
            .erased();
        Ok(Self {
            provider,
            safe,
            p256_owner_factory,
        })
    }

    pub fn entry_point(&self) -> Address {
        self.safe.entry_point
    }

    pub fn module_4337(&self) -> Address {
        self.safe.module_4337
    }

    /// Where a Device Key's owner contract lives, deployed or not.
    pub async fn device_owner_address(&self, x: U256, y: U256) -> Result<Address> {
        let factory = IP256OwnerFactory::new(self.p256_owner_factory, &self.provider);
        Ok(factory.getAddress(x, y).call().await.context("predicting the device owner")?)
    }

    /// Deploy the owner contract for a Device Key unless it already exists.
    pub async fn ensure_device_owner(&self, x: U256, y: U256) -> Result<Address> {
        let address = self.device_owner_address(x, y).await?;
        if !self.provider.get_code_at(address).await?.is_empty() {
            return Ok(address);
        }
        let factory = IP256OwnerFactory::new(self.p256_owner_factory, &self.provider);
        let receipt = retry_nonce(|| async { factory.create(x, y).send().await.map_err(anyhow::Error::from) })
            .await
            .context("sending the device owner deployment")?
            .get_receipt()
            .await
            .context("waiting for the device owner deployment")?;
        if !receipt.status() {
            return Err(anyhow!("device owner deployment reverted in {:#x}", receipt.transaction_hash));
        }
        if self.provider.get_code_at(address).await?.is_empty() {
            return Err(anyhow!("device owner deployment left no code at {address:#x}"));
        }
        Ok(address)
    }

    /// The Safe setup call for a fresh account: the three owners, threshold, and the
    /// 4337 module enabled and set as fallback handler in the same transaction.
    pub fn initializer(&self, owners: &[Address], threshold: u64) -> Bytes {
        let enable = ISafeModuleSetup::enableModulesCall {
            modules: vec![self.safe.module_4337],
        }
        .abi_encode();
        ISafe::setupCall {
            _owners: owners.to_vec(),
            _threshold: U256::from(threshold),
            to: self.safe.module_setup,
            data: enable.into(),
            fallbackHandler: self.safe.module_4337,
            paymentToken: Address::ZERO,
            payment: U256::ZERO,
            paymentReceiver: Address::ZERO,
        }
        .abi_encode()
        .into()
    }

    /// The address a Safe will land at for this initializer and salt, by asking the
    /// factory rather than re-deriving CREATE2 here.
    pub async fn predict_safe(&self, initializer: &Bytes, salt: U256) -> Result<Address> {
        let factory = ISafeProxyFactory::new(self.safe.proxy_factory, &self.provider);
        Ok(factory
            .createProxyWithNonce(self.safe.singleton, initializer.clone(), salt)
            .call()
            .await
            .context("predicting the Safe address")?)
    }

    pub async fn deploy_safe(&self, initializer: &Bytes, salt: U256) -> Result<Deployed> {
        let address = self.predict_safe(initializer, salt).await?;
        let factory = ISafeProxyFactory::new(self.safe.proxy_factory, &self.provider);
        let receipt = retry_nonce(|| async {
            factory.createProxyWithNonce(self.safe.singleton, initializer.clone(), salt).send().await.map_err(anyhow::Error::from)
        })
        .await
        .context("sending the Safe deployment")?
        .get_receipt()
            .await
            .context("waiting for the Safe deployment")?;
        if !receipt.status() {
            return Err(anyhow!("Safe deployment reverted in {:#x}", receipt.transaction_hash));
        }
        Ok(Deployed {
            address,
            tx_hash: receipt.transaction_hash,
        })
    }

    pub async fn has_code(&self, address: Address) -> Result<bool> {
        Ok(!self.provider.get_code_at(address).await?.is_empty())
    }

    pub async fn owners(&self, safe: Address) -> Result<(Vec<Address>, u64)> {
        let safe = ISafe::new(safe, &self.provider);
        let owners = safe.getOwners().call().await.context("reading owners")?;
        let threshold = safe.getThreshold().call().await.context("reading threshold")?;
        Ok((owners, threshold.to::<u64>()))
    }

    pub async fn module_enabled(&self, safe: Address) -> Result<bool> {
        let safe = ISafe::new(safe, &self.provider);
        Ok(safe.isModuleEnabled(self.safe.module_4337).call().await?)
    }

    pub async fn safe_nonce(&self, safe: Address) -> Result<U256> {
        let safe = ISafe::new(safe, &self.provider);
        Ok(safe.nonce().call().await.context("reading the Safe nonce")?)
    }

    pub fn swap_owner_calldata(prev: Address, old: Address, new: Address) -> Bytes {
        ISafe::swapOwnerCall {
            prevOwner: prev,
            oldOwner: old,
            newOwner: new,
        }
        .abi_encode()
        .into()
    }

    /// The hash the owners sign for a swap: a Safe transaction to the Safe itself,
    /// no value, no refund, at the given nonce. Asked of the Safe so the EIP-712
    /// domain is exactly its own.
    pub async fn swap_owner_hash(&self, safe: Address, data: &Bytes, nonce: U256) -> Result<B256> {
        let contract = ISafe::new(safe, &self.provider);
        Ok(contract
            .getTransactionHash(
                safe,
                U256::ZERO,
                data.clone(),
                0,
                U256::ZERO,
                U256::ZERO,
                U256::ZERO,
                Address::ZERO,
                Address::ZERO,
                nonce,
            )
            .call()
            .await
            .context("hashing the swap")?)
    }

    /// Submit the swap with the owners' signatures. The Safe checks them; this only
    /// pays the gas.
    pub async fn exec_swap_owner(&self, safe: Address, data: &Bytes, signatures: &[OwnerSignature]) -> Result<B256> {
        let contract = ISafe::new(safe, &self.provider);
        let packed = pack_signatures(signatures);
        let receipt = retry_nonce(|| async {
            contract
                .execTransaction(
                    safe,
                    U256::ZERO,
                    data.clone(),
                    0,
                    U256::ZERO,
                    U256::ZERO,
                    U256::ZERO,
                    Address::ZERO,
                    Address::ZERO,
                    packed.clone(),
                )
                .send()
                .await
                .map_err(anyhow::Error::from)
        })
        .await
        .context("sending the owner swap")?
        .get_receipt()
            .await
            .context("waiting for the owner swap")?;
        if !receipt.status() {
            return Err(anyhow!("owner swap reverted in {:#x}", receipt.transaction_hash));
        }
        Ok(receipt.transaction_hash)
    }
}

/// Safe wants signatures concatenated in ascending owner order.
pub fn pack_signatures(signatures: &[OwnerSignature]) -> Bytes {
    let mut sorted: Vec<&OwnerSignature> = signatures.iter().collect();
    sorted.sort_by_key(|entry| entry.owner);
    let mut out = Vec::with_capacity(65 * sorted.len());
    for entry in sorted {
        out.extend_from_slice(&entry.signature);
    }
    out.into()
}

/// The owner that precedes `owner` in the Safe's list, which `swapOwner` needs.
pub fn predecessor(owners: &[Address], owner: Address) -> Option<Address> {
    let index = owners.iter().position(|candidate| *candidate == owner)?;
    Some(if index == 0 { SENTINEL_OWNER } else { owners[index - 1] })
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy::primitives::address;

    #[test]
    fn signatures_pack_in_owner_order() {
        let high = address!("0xffffffffffffffffffffffffffffffffffffffff");
        let low = address!("0x0000000000000000000000000000000000000002");
        let packed = pack_signatures(&[
            OwnerSignature { owner: high, signature: [0xbb; 65] },
            OwnerSignature { owner: low, signature: [0xaa; 65] },
        ]);
        assert_eq!(packed.len(), 130);
        assert!(packed[..65].iter().all(|b| *b == 0xaa));
        assert!(packed[65..].iter().all(|b| *b == 0xbb));
    }

    #[test]
    fn the_first_owner_is_preceded_by_the_sentinel() {
        let a = address!("0x000000000000000000000000000000000000000a");
        let b = address!("0x000000000000000000000000000000000000000b");
        let c = address!("0x000000000000000000000000000000000000000c");
        assert_eq!(predecessor(&[a, b, c], a), Some(SENTINEL_OWNER));
        assert_eq!(predecessor(&[a, b, c], b), Some(a));
        assert_eq!(predecessor(&[a, b, c], c), Some(b));
        assert_eq!(predecessor(&[a, b], c), None);
    }

    #[test]
    fn swap_calldata_uses_the_safe_selector() {
        let data = SafeClient::swap_owner_calldata(SENTINEL_OWNER, Address::ZERO, Address::ZERO);
        assert_eq!(&data[..4], &ISafe::swapOwnerCall::SELECTOR);
        assert_eq!(data.len(), 4 + 3 * 32);
    }
}
