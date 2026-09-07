// Deposit addresses on chains that are not Arc.
//
// A person is shown a plain address on Base and sends USDC to it from an exchange or
// any wallet, with nothing to connect and nothing to sign. The address is a contract
// whose only power is burning its own USDC into a CCTP message addressed to that
// person's Arc account, and that account is part of the code the contract is deployed
// from, so the address itself is the proof of where the money can go.
//
// This service does two jobs: tell the app what address to show, and, when dollars land
// there, pay for the transaction that sends them on. It never holds the money.
// contracts/src/deposit is the rule book.

use alloy::network::EthereumWallet;
use alloy::primitives::{Address, B256};
use alloy::providers::fillers::{ChainIdFiller, GasFiller, NonceFiller, SimpleNonceManager};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy::rpc::types::Filter;
use alloy::signers::local::PrivateKeySigner;
use alloy::sol;
use alloy::sol_types::SolEvent;
use anyhow::{bail, Context, Result};
use std::sync::Arc;

sol! {
    #[sol(rpc)]
    interface IDepositFactory {
        function addressFor(address beneficiary) external view returns (address);
        function collect(bytes32 beneficiary) external returns (uint256);
        function collectBatch(bytes32[] calldata beneficiaries) external returns (uint256);
    }

    #[sol(rpc)]
    interface IERC20 {
        event Transfer(address indexed from, address indexed to, uint256 value);
    }
}

/// One chain we accept deposits on.
#[derive(Clone, Debug)]
pub struct DepositChain {
    pub key: String,
    pub name: String,
    pub chain_id: u64,
    pub usdc: Address,
}

pub struct DepositClient {
    provider: DynProvider,
    relayer: Address,
    pub chain: DepositChain,
    pub factory: Address,
    // The relayer's nonce is read per send, so two sweeps in flight would collide.
    send_lock: Arc<tokio::sync::Mutex<()>>,
}

impl DepositClient {
    pub fn new(rpc_url: &str, private_key: &str, factory: Address, chain: DepositChain) -> Result<Self> {
        let signer: PrivateKeySigner = private_key.trim().parse().context("parsing the sweeper key")?;
        let relayer = signer.address();
        let url = rpc_url.parse().context("parsing the deposit chain RPC URL")?;
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
            relayer,
            chain,
            factory,
            send_lock: Arc::new(tokio::sync::Mutex::new(())),
        })
    }

    pub fn relayer(&self) -> Address {
        self.relayer
    }

    /// The chain is the source of truth for the address, not a copy of the maths here:
    /// a person is about to send money to it, so it is worth the call.
    pub async fn address_for(&self, arc_account: Address) -> Result<Address> {
        let factory = IDepositFactory::new(self.factory, &self.provider);
        factory
            .addressFor(arc_account)
            .call()
            .await
            .context("asking the deposit factory for an address")
    }

    /// Refuses to answer at all if the factory is not there, rather than handing out an
    /// address that nothing can ever sweep.
    pub async fn ready(&self) -> bool {
        matches!(self.provider.get_code_at(self.factory).await, Ok(code) if !code.is_empty())
    }

    pub async fn block_number(&self) -> Result<u64> {
        Ok(self.provider.get_block_number().await?)
    }

    /// Every USDC transfer into any of these addresses in a block range, one query. The
    /// recipient topic takes a list, so a thousand deposit addresses cost one call.
    pub async fn usdc_received(&self, recipients: &[Address], from_block: u64, to_block: u64) -> Result<Vec<Address>> {
        if recipients.is_empty() {
            return Ok(Vec::new());
        }
        let filter = Filter::new()
            .address(self.chain.usdc)
            .event_signature(IERC20::Transfer::SIGNATURE_HASH)
            .topic2(recipients.iter().map(|a| a.into_word()).collect::<Vec<B256>>())
            .from_block(from_block)
            .to_block(to_block);
        let logs = self.provider.get_logs(&filter).await.context("reading deposit transfers")?;
        let mut touched: Vec<Address> = Vec::new();
        for log in logs {
            if let Ok(event) = IERC20::Transfer::decode_log(&log.inner) {
                if !touched.contains(&event.to) {
                    touched.push(event.to);
                }
            }
        }
        Ok(touched)
    }

    /// Deploy each vault if needed and send its dollars to Arc, in one transaction.
    /// Vaults with nothing in them are skipped by the contract rather than reverting the
    /// batch, so a stale list is harmless.
    pub async fn collect(&self, beneficiaries: &[Address]) -> Result<B256> {
        if beneficiaries.is_empty() {
            bail!("nothing to collect");
        }
        let _guard = self.send_lock.lock().await;
        let factory = IDepositFactory::new(self.factory, &self.provider);
        let keys: Vec<B256> = beneficiaries.iter().map(|a| a.into_word()).collect();
        let receipt = factory
            .collectBatch(keys)
            .send()
            .await
            .context("sending collectBatch")?
            .get_receipt()
            .await
            .context("waiting for collectBatch")?;
        if !receipt.status() {
            bail!("collectBatch reverted in {:#x}", receipt.transaction_hash);
        }
        Ok(receipt.transaction_hash)
    }
}

/// The chains this build accepts deposits on. Base first because it is where dollars are
/// cheapest to move and what most exchanges withdraw to.
pub fn chains_for(chain_id: u64) -> Vec<DepositChain> {
    match chain_id {
        // Base Sepolia, the testnet pair for Arc testnet.
        84532 => vec![DepositChain {
            key: "base".into(),
            name: "Base".into(),
            chain_id: 84532,
            usdc: "0x036CbD53842c5426634e7929541eC2318f3dCF7e".parse().unwrap(),
        }],
        8453 => vec![DepositChain {
            key: "base".into(),
            name: "Base".into(),
            chain_id: 8453,
            usdc: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913".parse().unwrap(),
        }],
        _ => Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_chains_are_known_by_id() {
        assert_eq!(chains_for(84532)[0].name, "Base");
        assert_eq!(chains_for(8453)[0].name, "Base");
        assert!(chains_for(1).is_empty());
    }

    #[test]
    fn base_usdc_differs_between_testnet_and_mainnet() {
        assert_ne!(chains_for(84532)[0].usdc, chains_for(8453)[0].usdc);
    }
}
