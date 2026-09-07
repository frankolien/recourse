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
    /// Where to read this chain, unless the deployment names its own. A public
    /// endpoint is enough for a job that reads a log range once a cycle, and having
    /// one means adding a chain needs a deploy rather than a pile of settings.
    pub rpc: String,
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

/// The chains this build accepts deposits on, and where to read each one.
///
/// The factory holds the same address on every chain, so one person has one deposit
/// address across all of them. A chain listed here but without the factory deployed on
/// it costs nothing: the sweeper checks for the code and idles, and the dollars sit in
/// the vault until the factory arrives, which is the whole point of an address that is
/// known before it exists.
pub fn chains_for(chain_id: u64) -> Vec<DepositChain> {
    let rows: &[(&str, &str, u64, &str, &str)] = match chain_id {
        // Testnets, paired with Arc testnet.
        5042002 | 84532 => &[
            ("base", "Base", 84532, "0x036CbD53842c5426634e7929541eC2318f3dCF7e", "https://sepolia.base.org"),
            ("arbitrum", "Arbitrum", 421614, "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d", "https://sepolia-rollup.arbitrum.io/rpc"),
            ("optimism", "Optimism", 11155420, "0x5fd84259d66Cd46123540766Be93DFE6D43130D7", "https://sepolia.optimism.io"),
            ("ethereum", "Ethereum", 11155111, "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", "https://ethereum-sepolia-rpc.publicnode.com"),
            ("polygon", "Polygon", 80002, "0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582", "https://polygon-amoy-bor-rpc.publicnode.com"),
            ("avalanche", "Avalanche", 43113, "0x5425890298aed601595a70AB815c96711a31Bc65", "https://api.avax-test.network/ext/bc/C/rpc"),
            ("unichain", "Unichain", 1301, "0x31d0220469e10c4E71834a79b1f276d740d3768F", "https://sepolia.unichain.org"),
            ("linea", "Linea", 59141, "0xFEce4462D57bD51A6A552365A011b95f0E16d9B7", "https://rpc.sepolia.linea.build"),
        ],
        5042 | 8453 => &[
            ("base", "Base", 8453, "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", "https://mainnet.base.org"),
            ("arbitrum", "Arbitrum", 42161, "0xaf88d065e77c8cC2239327C5EDb3A432268e5831", "https://arb1.arbitrum.io/rpc"),
            ("optimism", "Optimism", 10, "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85", "https://mainnet.optimism.io"),
            ("ethereum", "Ethereum", 1, "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", "https://ethereum-rpc.publicnode.com"),
            ("polygon", "Polygon", 137, "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359", "https://polygon-bor-rpc.publicnode.com"),
            ("avalanche", "Avalanche", 43114, "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E", "https://api.avax.network/ext/bc/C/rpc"),
            ("unichain", "Unichain", 130, "0x078D782b760474a361dDA0AF3839290b0EF57AD6", "https://mainnet.unichain.org"),
            ("linea", "Linea", 59144, "0x176211869cA2b568f2A7D4EE941E073a821EE1ff", "https://rpc.linea.build"),
        ],
        _ => &[],
    };
    rows.iter()
        .map(|(key, name, id, usdc, rpc)| DepositChain {
            key: (*key).into(),
            name: (*name).into(),
            chain_id: *id,
            usdc: usdc.parse().expect("deposit chain USDC address"),
            rpc: (*rpc).into(),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base_leads_and_arc_ids_resolve() {
        // The Arc chain the service runs on picks the set, so a testnet build can
        // never be handed a mainnet chain by a stray setting.
        assert_eq!(chains_for(5042002)[0].name, "Base");
        assert_eq!(chains_for(5042)[0].name, "Base");
        assert_eq!(chains_for(84532)[0].name, "Base");
        assert!(chains_for(1).is_empty());
    }

    #[test]
    fn every_chain_is_listed_once_with_its_own_token() {
        for arc in [5042002u64, 5042] {
            let chains = chains_for(arc);
            assert_eq!(chains.len(), 8, "eight source chains");
            for (i, chain) in chains.iter().enumerate() {
                for other in chains.iter().skip(i + 1) {
                    assert_ne!(chain.key, other.key, "a chain key is listed twice");
                    assert_ne!(chain.chain_id, other.chain_id, "a chain id is listed twice");
                    assert_ne!(chain.usdc, other.usdc, "two chains share a USDC address");
                }
                assert!(chain.rpc.starts_with("https://"), "{} needs an endpoint", chain.key);
            }
        }
    }

    #[test]
    fn testnet_and_mainnet_never_share_a_token() {
        for testnet in chains_for(5042002) {
            for mainnet in chains_for(5042) {
                assert_ne!(testnet.usdc, mainnet.usdc);
                assert_ne!(testnet.chain_id, mainnet.chain_id);
            }
        }
    }
}
