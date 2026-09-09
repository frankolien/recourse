//! An account's Safe: provisioning at enrolment, and swapping the Device Key at
//! recovery.
//!
//! The rules that matter live here rather than in the handlers or the chain client:
//! an account has one Safe and one Device Key at a time; a Device Key changes only
//! through a rotation that a verified email code opened and the Cloud Key signed; and
//! the Recovery Key signs a `swapOwner` on the account's own Safe and nothing else,
//! because this module is the only caller that asks it to sign and this is the only
//! transaction it builds.

use alloy::primitives::{Address, Signature, B256, U256};
use chrono::{DateTime, Duration, Utc};
use rand::RngCore;
use serde::Serialize;
use sqlx::PgPool;

use crate::services::account_sessions::AccountAuthError;
use crate::services::recovery::{self, Mailer, RecoveryVault, PURPOSE_CLOUD_ROTATION, PURPOSE_DEVICE_ROTATION};
use crate::services::safe::{predecessor, OwnerSignature, SafeClient};
use crate::services::handles;

pub const THRESHOLD: u64 = 2;

const STATUS_DEPLOYING: &str = "deploying";
const STATUS_LIVE: &str = "live";
const ROTATION_PREPARED: &str = "prepared";
const ROTATION_EXECUTED: &str = "executed";
const ROTATION_CANCELLED: &str = "cancelled";

/// How long a scheduled key change waits before it can be executed.
///
/// Replacing the Device Key takes the Cloud Key and the Recovery Key, which is the
/// pair someone holds who has taken an Apple ID and an inbox. Replacing the Cloud Key
/// takes the Device Key and the Recovery Key, which needs the phone itself, in hand
/// and unlocked. The phone is the harder thing to steal, so it buys the shorter wait.
/// The other direction gets a full day, which is long enough to read an email and stop
/// it. Argent waits two days, Xend one, Candide fourteen; nobody serious waits none.
const DEVICE_ROTATION_DELAY: Duration = Duration::hours(1);
const CLOUD_ROTATION_DELAY: Duration = Duration::hours(24);

/// Everything the account endpoints need, each piece optional so the server still
/// boots without a deployer key or a vault and says precisely what is missing.
#[derive(Clone)]
pub struct SmartAccounts {
    pub safe: Option<SafeClient>,
    pub vault: Option<RecoveryVault>,
    pub mailer: Option<Mailer>,
}

impl SmartAccounts {
    fn safe(&self) -> Result<&SafeClient, AccountAuthError> {
        self.safe
            .as_ref()
            .ok_or_else(|| AccountAuthError::Internal("accounts are not switched on for this server yet".into()))
    }

    fn vault(&self) -> Result<&RecoveryVault, AccountAuthError> {
        self.vault
            .as_ref()
            .ok_or_else(|| AccountAuthError::Internal("recovery is not switched on for this server yet".into()))
    }

    fn mailer(&self) -> Result<&Mailer, AccountAuthError> {
        self.mailer
            .as_ref()
            .ok_or_else(|| AccountAuthError::Internal("recovery email is not switched on for this server yet".into()))
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AccountView {
    pub safe: String,
    pub cloud_owner: String,
    pub device_owner: String,
    /// The Device Key's coordinates, so a phone can tell whether the key it holds is
    /// the one the account is bound to, without re-deriving the owner address.
    pub device_x: String,
    pub device_y: String,
    pub recovery_owner: String,
    pub threshold: i32,
    pub status: String,
    pub entry_point: String,
    pub module: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RotationPlan {
    pub rotation_id: i64,
    pub safe_tx_hash: String,
    pub old_device_owner: String,
    pub new_device_owner: String,
    pub prev_owner: String,
    pub safe_nonce: String,
    /// When this may be executed. Until then the account's other keys can stop it.
    pub ready_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CloudRotationPlan {
    pub rotation_id: i64,
    pub safe_tx_hash: String,
    pub old_cloud_owner: String,
    pub new_cloud_owner: String,
    pub prev_owner: String,
    pub safe_nonce: String,
    pub ready_at: DateTime<Utc>,
}

/// A key change waiting out its delay, as the app shows it to whoever still holds a
/// key. The point of showing it is the cancel button beside it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PendingRecovery {
    pub rotation_id: i64,
    /// "device" or "cloud": which key is being replaced.
    pub kind: String,
    pub ready_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

/// A scheduled change may only run once its clock is out and while nobody has stopped
/// it. Both answers are refusals the person can act on, not internal errors.
fn guard_ready(ready_at: Option<DateTime<Utc>>, cancelled_at: Option<DateTime<Utc>>) -> Result<(), AccountAuthError> {
    if cancelled_at.is_some() {
        return Err(AccountAuthError::Conflict("this recovery was stopped from one of your other keys".into()));
    }
    match ready_at {
        Some(ready) if Utc::now() < ready => Err(AccountAuthError::Conflict(format!(
            "this recovery can be completed after {}",
            ready.to_rfc3339()
        ))),
        _ => Ok(()),
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RotationOutcome {
    pub tx_hash: String,
    pub device_owner: String,
}

#[derive(Debug, sqlx::FromRow)]
struct Row {
    safe_address: String,
    salt_nonce: String,
    cloud_owner: String,
    device_owner: String,
    device_x: String,
    device_y: String,
    recovery_owner: String,
    threshold: i32,
    status: String,
}

fn hex_address(address: Address) -> String {
    format!("{address:#x}")
}

fn hex_u256(value: U256) -> String {
    format!("0x{value:064x}")
}

fn parse_address(stored: &str) -> Result<Address, AccountAuthError> {
    stored
        .parse()
        .map_err(|error| AccountAuthError::Internal(format!("stored address is corrupt: {error}")))
}

fn parse_u256(stored: &str) -> Result<U256, AccountAuthError> {
    U256::from_str_radix(stored.trim_start_matches("0x"), 16)
        .map_err(|error| AccountAuthError::Internal(format!("stored number is corrupt: {error}")))
}

fn chain(error: anyhow::Error) -> AccountAuthError {
    AccountAuthError::Internal(format!("{error:#}"))
}

async fn row(pool: &PgPool, account_id: i64) -> Result<Option<Row>, AccountAuthError> {
    sqlx::query_as::<_, Row>(
        "SELECT safe_address, salt_nonce, cloud_owner, device_owner, device_x, device_y, \
                recovery_owner, threshold, status \
         FROM smart_accounts WHERE account_id = $1",
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading smart account: {error}")))
}

fn view(row: &Row, safe: &SafeClient) -> AccountView {
    AccountView {
        safe: row.safe_address.clone(),
        cloud_owner: row.cloud_owner.clone(),
        device_owner: row.device_owner.clone(),
        device_x: row.device_x.clone(),
        device_y: row.device_y.clone(),
        recovery_owner: row.recovery_owner.clone(),
        threshold: row.threshold,
        status: row.status.clone(),
        entry_point: hex_address(safe.entry_point()),
        module: hex_address(safe.module_4337()),
    }
}

pub async fn current(pool: &PgPool, service: &SmartAccounts, account_id: i64) -> Result<Option<AccountView>, AccountAuthError> {
    let safe = service.safe()?;
    Ok(row(pool, account_id).await?.map(|row| view(&row, safe)))
}

/// A fresh salt and the address the Safe takes for these owners.
async fn plan(safe: &SafeClient, owners: &[Address; 3]) -> Result<(U256, Address), AccountAuthError> {
    let mut salt_bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut salt_bytes);
    let salt = U256::from_be_bytes(salt_bytes);
    let initializer = safe.initializer(owners, THRESHOLD);
    let address = safe.predict_safe(&initializer, salt).await.map_err(chain)?;
    Ok((salt, address))
}

/// Point a row that never deployed at the keys the phone holds now.
///
/// The row was written before the first deployment and that deployment failed, so
/// nothing exists at its address, no phone was ever shown it, and the handle still
/// points at the old key. The Recovery Key stays; the address moves with the owners.
/// The abandoned address and salt go to the log so the Safe could still be deployed
/// there by hand if money ever turned up at it.
async fn rekey(
    pool: &PgPool,
    safe: &SafeClient,
    account_id: i64,
    abandoned: &Row,
    cloud_owner: Address,
    device_owner: Address,
    device_x: U256,
    device_y: U256,
) -> Result<Row, AccountAuthError> {
    let recovery_owner = parse_address(&abandoned.recovery_owner)?;
    let (salt, address) = plan(safe, &[cloud_owner, device_owner, recovery_owner]).await?;
    let updated = sqlx::query(
        "UPDATE smart_accounts \
         SET safe_address = $2, salt_nonce = $3, cloud_owner = $4, device_owner = $5, device_x = $6, device_y = $7, \
             updated_at = now() \
         WHERE account_id = $1 AND status = $8 AND safe_address = $9",
    )
    .bind(account_id)
    .bind(hex_address(address))
    .bind(hex_u256(salt))
    .bind(hex_address(cloud_owner))
    .bind(hex_address(device_owner))
    .bind(hex_u256(device_x))
    .bind(hex_u256(device_y))
    .bind(STATUS_DEPLOYING)
    .bind(&abandoned.safe_address)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("re-keying smart account: {error}")))?;
    if updated.rows_affected() == 0 {
        return Err(AccountAuthError::Conflict("this account's wallet changed underneath; try again".into()));
    }
    tracing::info!(
        "smart account for account {account_id} re-keyed to {address:#x}; {} (salt {}) was never deployed",
        abandoned.safe_address, abandoned.salt_nonce
    );
    row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::Internal("smart account vanished after re-keying".into()))
}

/// Create the account's Safe, or finish creating it, or return it.
///
/// The phone brings the two keys it holds; the Recovery Key is minted here. The
/// address is fixed before anything is deployed, so a crash between the two
/// deployments leaves a row in `deploying` that the next call completes at the same
/// address. A different Device Key for an account that already has one is refused:
/// that is a recovery, and it goes through the email code.
pub async fn provision(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    cloud_owner: Address,
    device_x: U256,
    device_y: U256,
) -> Result<AccountView, AccountAuthError> {
    let safe = service.safe()?;
    let vault = service.vault()?;

    let device_owner = safe.device_owner_address(device_x, device_y).await.map_err(chain)?;

    let existing = match row(pool, account_id).await? {
        Some(existing) => {
            let same_cloud = parse_address(&existing.cloud_owner)? == cloud_owner;
            let same_device = parse_address(&existing.device_owner)? == device_owner;
            if same_cloud && same_device {
                if existing.status == STATUS_LIVE {
                    return Ok(view(&existing, safe));
                }
                existing
            } else if existing.status != STATUS_LIVE
                && !safe.has_code(parse_address(&existing.safe_address)?).await.map_err(chain)?
            {
                // A first deployment that failed leaves a row keyed to whatever phone
                // asked; if that phone's keys are gone, the one here now takes over.
                rekey(pool, safe, account_id, &existing, cloud_owner, device_owner, device_x, device_y).await?
            } else if !same_cloud {
                return Err(AccountAuthError::Conflict(
                    "this account already has a wallet under a different cloud key".into(),
                ));
            } else {
                return Err(AccountAuthError::Conflict(
                    "this account already has a device key; restore this phone through recovery".into(),
                ));
            }
        }
        None => {
            let recovery_owner = recovery::ensure_signer(pool, vault, account_id).await?;
            let (salt, address) = plan(safe, &[cloud_owner, device_owner, recovery_owner]).await?;

            sqlx::query(
                "INSERT INTO smart_accounts \
                 (account_id, safe_address, salt_nonce, cloud_owner, device_owner, device_x, device_y, recovery_owner, threshold, status) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) \
                 ON CONFLICT (account_id) DO NOTHING",
            )
            .bind(account_id)
            .bind(hex_address(address))
            .bind(hex_u256(salt))
            .bind(hex_address(cloud_owner))
            .bind(hex_address(device_owner))
            .bind(hex_u256(device_x))
            .bind(hex_u256(device_y))
            .bind(hex_address(recovery_owner))
            .bind(THRESHOLD as i32)
            .bind(STATUS_DEPLOYING)
            .execute(pool)
            .await
            .map_err(|error| AccountAuthError::Internal(format!("recording smart account: {error}")))?;

            // Two provisions racing insert once; both continue with whatever landed.
            row(pool, account_id)
                .await?
                .ok_or_else(|| AccountAuthError::Internal("smart account vanished after insert".into()))?
        }
    };

    let safe_address = parse_address(&existing.safe_address)?;
    let owners = [
        cloud_owner,
        device_owner,
        parse_address(&existing.recovery_owner)?,
    ];
    let initializer = safe.initializer(&owners, THRESHOLD);
    let salt = parse_u256(&existing.salt_nonce)?;

    safe.ensure_device_owner(device_x, device_y).await.map_err(chain)?;
    if !safe.has_code(safe_address).await.map_err(chain)? {
        let deployed = safe.deploy_safe(&initializer, salt).await.map_err(chain)?;
        tracing::info!(
            "smart account deployed for account {account_id} at {:#x} in {:#x}",
            deployed.address, deployed.tx_hash
        );
        if deployed.address != safe_address {
            return Err(AccountAuthError::Internal(format!(
                "Safe landed at {:#x}, expected {safe_address:#x}",
                deployed.address
            )));
        }
    }

    // Trust the chain, not the deployment call: the row goes live only once the Safe
    // reports exactly the owner set and threshold the account was promised.
    let (onchain_owners, threshold) = safe.owners(safe_address).await.map_err(chain)?;
    let mut expected: Vec<Address> = owners.to_vec();
    expected.sort();
    let mut found = onchain_owners.clone();
    found.sort();
    if found != expected || threshold != THRESHOLD {
        return Err(AccountAuthError::Internal(
            "the deployed Safe does not have the expected owners".into(),
        ));
    }
    if !safe.module_enabled(safe_address).await.map_err(chain)? {
        return Err(AccountAuthError::Internal("the deployed Safe has no 4337 module".into()));
    }

    sqlx::query("UPDATE smart_accounts SET status = $2, updated_at = now() WHERE account_id = $1")
        .bind(account_id)
        .bind(STATUS_LIVE)
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("marking smart account live: {error}")))?;

    // The handle follows the money.
    handles::repoint(pool, account_id, &hex_address(safe_address)).await?;

    let live = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::Internal("smart account vanished".into()))?;
    Ok(view(&live, safe))
}

pub async fn issue_recovery_code(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    email: Option<&str>,
) -> Result<recovery::IssuedChallenge, AccountAuthError> {
    let mailer = service.mailer()?;
    let email = email
        .filter(|address| !address.trim().is_empty())
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no email to send a code to".into()))?;
    if row(pool, account_id).await?.is_none() {
        return Err(AccountAuthError::BadRequest("this account has no wallet to recover".into()));
    }
    recovery::issue_code(pool, mailer, account_id, email, PURPOSE_DEVICE_ROTATION).await
}

/// The same proof of inbox, for the other key. Kept separate from the device one so a
/// code emailed to swap a phone cannot be spent to swap an iCloud instead.
pub async fn issue_cloud_recovery_code(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    email: Option<&str>,
) -> Result<recovery::IssuedChallenge, AccountAuthError> {
    let mailer = service.mailer()?;
    let email = email
        .filter(|address| !address.trim().is_empty())
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no email to send a code to".into()))?;
    if row(pool, account_id).await?.is_none() {
        return Err(AccountAuthError::BadRequest("this account has no wallet to recover".into()));
    }
    recovery::issue_code(pool, mailer, account_id, email, PURPOSE_CLOUD_ROTATION).await
}

pub async fn verify_cloud_recovery_code(
    pool: &PgPool,
    account_id: i64,
    code: &str,
) -> Result<recovery::RecoveryGrant, AccountAuthError> {
    recovery::verify_code(pool, account_id, PURPOSE_CLOUD_ROTATION, code).await
}

pub async fn verify_recovery_code(
    pool: &PgPool,
    account_id: i64,
    code: &str,
) -> Result<recovery::RecoveryGrant, AccountAuthError> {
    recovery::verify_code(pool, account_id, PURPOSE_DEVICE_ROTATION, code).await
}

/// Fix the swap and hand its hash to the phone for the Cloud Key to sign.
///
/// The new Device Key's owner contract is deployed here, before the swap is staged,
/// so the Safe transaction names a contract that exists. Its address is a function
/// of the key, so the phone can check it is being asked to sign for its own key.
/// Give up a wallet whose keys are gone, proven by the emailed code, so the account
/// can make a new one. The row moves to the abandoned table rather than vanishing:
/// the Safe is still on chain and may still hold money a found key could reach.
pub async fn abandon_wallet(pool: &PgPool, account_id: i64, grant_id: &str) -> Result<(), AccountAuthError> {
    recovery::assert_grant(pool, account_id, PURPOSE_DEVICE_ROTATION, grant_id).await?;
    if !recovery::consume_grant(pool, account_id, grant_id).await? {
        return Err(AccountAuthError::Unauthorized("that code was already used; ask for a new one".into()));
    }
    let mut tx = pool
        .begin()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("starting the abandon: {error}")))?;
    let moved = sqlx::query(
        "INSERT INTO smart_accounts_abandoned \
         (account_id, safe_address, salt_nonce, cloud_owner, device_owner, device_x, device_y, recovery_owner, threshold, status, created_at) \
         SELECT account_id, safe_address, salt_nonce, cloud_owner, device_owner, device_x, device_y, recovery_owner, threshold, status, created_at \
         FROM smart_accounts WHERE account_id = $1",
    )
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("keeping the abandoned wallet: {error}")))?;
    if moved.rows_affected() == 0 {
        return Err(AccountAuthError::BadRequest("this account has no wallet to abandon".into()));
    }
    sqlx::query("DELETE FROM smart_accounts WHERE account_id = $1")
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("releasing the account: {error}")))?;
    tx.commit()
        .await
        .map_err(|error| AccountAuthError::Internal(format!("finishing the abandon: {error}")))?;
    Ok(())
}

pub async fn prepare_rotation(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    grant_id: &str,
    new_x: U256,
    new_y: U256,
) -> Result<RotationPlan, AccountAuthError> {
    let safe = service.safe()?;
    recovery::assert_grant(pool, account_id, PURPOSE_DEVICE_ROTATION, grant_id).await?;

    let account = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no wallet to recover".into()))?;
    if account.status != STATUS_LIVE {
        return Err(AccountAuthError::Conflict("this account's wallet is still being set up".into()));
    }
    let safe_address = parse_address(&account.safe_address)?;
    let old_device = parse_address(&account.device_owner)?;

    let new_device = safe.ensure_device_owner(new_x, new_y).await.map_err(chain)?;
    if new_device == old_device {
        return Err(AccountAuthError::Conflict("that is already this account's device key".into()));
    }

    let (owners, _) = safe.owners(safe_address).await.map_err(chain)?;
    let prev = predecessor(&owners, old_device).ok_or_else(|| {
        AccountAuthError::Conflict("the Safe's owners no longer match this account; contact support".into())
    })?;
    let nonce = safe.safe_nonce(safe_address).await.map_err(chain)?;
    let data = SafeClient::swap_owner_calldata(prev, old_device, new_device);
    let hash = safe.swap_owner_hash(safe_address, &data, nonce).await.map_err(chain)?;
    let ready_at = Utc::now() + DEVICE_ROTATION_DELAY;

    let (rotation_id,): (i64,) = sqlx::query_as(
        "INSERT INTO device_rotations \
         (account_id, grant_id, old_device_owner, new_device_owner, new_device_x, new_device_y, prev_owner, safe_nonce, safe_tx_hash, status, ready_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id",
    )
    .bind(account_id)
    .bind(grant_id)
    .bind(hex_address(old_device))
    .bind(hex_address(new_device))
    .bind(hex_u256(new_x))
    .bind(hex_u256(new_y))
    .bind(hex_address(prev))
    .bind(hex_u256(nonce))
    .bind(format!("{hash:#x}"))
    .bind(ROTATION_PREPARED)
    .bind(ready_at)
    .fetch_one(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("recording the rotation: {error}")))?;

    Ok(RotationPlan {
        rotation_id,
        ready_at,
        safe_tx_hash: format!("{hash:#x}"),
        old_device_owner: hex_address(old_device),
        new_device_owner: hex_address(new_device),
        prev_owner: hex_address(prev),
        safe_nonce: hex_u256(nonce),
    })
}

#[derive(Debug, sqlx::FromRow)]
struct RotationRow {
    grant_id: String,
    old_device_owner: String,
    new_device_owner: String,
    new_device_x: String,
    new_device_y: String,
    prev_owner: String,
    safe_nonce: String,
    safe_tx_hash: String,
    status: String,
    ready_at: Option<DateTime<Utc>>,
    cancelled_at: Option<DateTime<Utc>>,
}

/// Add the Recovery Key's signature to the Cloud Key's and submit the swap.
///
/// The transaction is rebuilt from what was stored at prepare time and its hash
/// compared, so the Recovery Key only ever signs the swap this module built. The
/// Cloud Key's signature is checked here too, before anything is unsealed: a wrong
/// signature costs nothing on-chain and unseals nothing.
pub async fn execute_rotation(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    rotation_id: i64,
    cloud_signature: [u8; 65],
) -> Result<RotationOutcome, AccountAuthError> {
    let safe = service.safe()?;
    let vault = service.vault()?;

    let rotation = sqlx::query_as::<_, RotationRow>(
        "SELECT grant_id, old_device_owner, new_device_owner, new_device_x, new_device_y, prev_owner, \
                safe_nonce, safe_tx_hash, status, ready_at, cancelled_at \
         FROM device_rotations WHERE id = $1 AND account_id = $2",
    )
    .bind(rotation_id)
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading the rotation: {error}")))?
    .ok_or_else(|| AccountAuthError::BadRequest("no such rotation".into()))?;
    if rotation.status != ROTATION_PREPARED {
        return Err(AccountAuthError::Conflict("this rotation was already used".into()));
    }
    guard_ready(rotation.ready_at, rotation.cancelled_at)?;
    recovery::assert_grant(pool, account_id, PURPOSE_DEVICE_ROTATION, &rotation.grant_id).await?;

    let account = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no wallet".into()))?;
    let safe_address = parse_address(&account.safe_address)?;
    let cloud_owner = parse_address(&account.cloud_owner)?;
    let recovery_owner = parse_address(&account.recovery_owner)?;
    let old_device = parse_address(&rotation.old_device_owner)?;
    let new_device = parse_address(&rotation.new_device_owner)?;
    let prev = parse_address(&rotation.prev_owner)?;
    let nonce = parse_u256(&rotation.safe_nonce)?;
    let stored_hash: B256 = rotation
        .safe_tx_hash
        .parse()
        .map_err(|_| AccountAuthError::Internal("stored hash is corrupt".into()))?;

    if parse_address(&account.device_owner)? != old_device {
        return Err(AccountAuthError::Conflict("the device key changed since this rotation was prepared".into()));
    }
    if safe.safe_nonce(safe_address).await.map_err(chain)? != nonce {
        return Err(AccountAuthError::Conflict("the Safe moved on; prepare the rotation again".into()));
    }

    let data = SafeClient::swap_owner_calldata(prev, old_device, new_device);
    let hash = safe.swap_owner_hash(safe_address, &data, nonce).await.map_err(chain)?;
    if hash != stored_hash {
        return Err(AccountAuthError::Internal("the swap no longer hashes to what was prepared".into()));
    }

    let signature = Signature::try_from(&cloud_signature[..])
        .map_err(|_| AccountAuthError::BadRequest("cloud signature is malformed".into()))?;
    let signed_by = signature
        .recover_address_from_prehash(&hash)
        .map_err(|_| AccountAuthError::BadRequest("cloud signature does not recover".into()))?;
    if signed_by != cloud_owner {
        return Err(AccountAuthError::Unauthorized("that signature is not the account's cloud key".into()));
    }

    let recovery_signature = recovery::sign_safe_hash(pool, vault, account_id, hash).await?;
    let tx_hash = safe
        .exec_swap_owner(
            safe_address,
            &data,
            &[
                OwnerSignature { owner: cloud_owner, signature: cloud_signature },
                OwnerSignature { owner: recovery_owner, signature: recovery_signature },
            ],
        )
        .await
        .map_err(chain)?;

    // The chain has moved; the rows follow, and the grant is spent whether or not
    // the bookkeeping below succeeds.
    recovery::consume_grant(pool, account_id, &rotation.grant_id).await?;
    sqlx::query(
        "UPDATE smart_accounts SET device_owner = $2, device_x = $3, device_y = $4, updated_at = now() \
         WHERE account_id = $1",
    )
    .bind(account_id)
    .bind(hex_address(new_device))
    .bind(&rotation.new_device_x)
    .bind(&rotation.new_device_y)
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("recording the new device key: {error}")))?;
    sqlx::query(
        "UPDATE device_rotations SET status = $2, tx_hash = $3, executed_at = $4 WHERE id = $1",
    )
    .bind(rotation_id)
    .bind(ROTATION_EXECUTED)
    .bind(format!("{tx_hash:#x}"))
    .bind(Utc::now())
    .execute(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("closing the rotation: {error}")))?;

    Ok(RotationOutcome {
        tx_hash: format!("{tx_hash:#x}"),
        device_owner: hex_address(new_device),
    })
}

/// Replacing the Cloud Key, for someone whose iCloud is gone and who never set a
/// recovery PIN. The Device Key on the phone signs, the Recovery Key here co-signs,
/// and the phone submits it: this module never needs to pack a contract signature,
/// because the app already does that for every payment it makes.
///
/// Nothing is signed at this point. The swap is built and parked, the old Cloud Key
/// is told, and a day has to pass before the Recovery Key will put its name to it.
pub async fn prepare_cloud_rotation(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    grant_id: &str,
    new_cloud: Address,
) -> Result<CloudRotationPlan, AccountAuthError> {
    let safe = service.safe()?;
    recovery::assert_grant(pool, account_id, PURPOSE_CLOUD_ROTATION, grant_id).await?;

    let account = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no wallet to recover".into()))?;
    if account.status != STATUS_LIVE {
        return Err(AccountAuthError::Conflict("this account's wallet is still being set up".into()));
    }
    let safe_address = parse_address(&account.safe_address)?;
    let old_cloud = parse_address(&account.cloud_owner)?;
    if new_cloud == old_cloud {
        return Err(AccountAuthError::Conflict("that is already this account's cloud key".into()));
    }
    // A new key that is already an owner would leave the Safe with two of the same
    // and a threshold it can no longer meet.
    let (owners, _) = safe.owners(safe_address).await.map_err(chain)?;
    if owners.contains(&new_cloud) {
        return Err(AccountAuthError::Conflict("that key is already on this account".into()));
    }
    if new_cloud == Address::ZERO {
        return Err(AccountAuthError::BadRequest("that is not a key".into()));
    }

    // One at a time. Two pending swaps of the same owner would both build against the
    // same nonce and the second would be dead on arrival.
    let pending: Option<(i64,)> = sqlx::query_as(
        "SELECT id FROM cloud_rotations WHERE account_id = $1 AND status = $2 AND cancelled_at IS NULL",
    )
    .bind(account_id)
    .bind(ROTATION_PREPARED)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading cloud rotations: {error}")))?;
    if pending.is_some() {
        return Err(AccountAuthError::Conflict("a cloud key change is already waiting on this account".into()));
    }

    let prev = predecessor(&owners, old_cloud).ok_or_else(|| {
        AccountAuthError::Conflict("the Safe's owners no longer match this account; contact support".into())
    })?;
    let nonce = safe.safe_nonce(safe_address).await.map_err(chain)?;
    let data = SafeClient::swap_owner_calldata(prev, old_cloud, new_cloud);
    let hash = safe.swap_owner_hash(safe_address, &data, nonce).await.map_err(chain)?;
    let ready_at = Utc::now() + CLOUD_ROTATION_DELAY;

    let (rotation_id,): (i64,) = sqlx::query_as(
        "INSERT INTO cloud_rotations \
         (account_id, grant_id, old_cloud_owner, new_cloud_owner, prev_owner, safe_nonce, safe_tx_hash, status, ready_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id",
    )
    .bind(account_id)
    .bind(grant_id)
    .bind(hex_address(old_cloud))
    .bind(hex_address(new_cloud))
    .bind(hex_address(prev))
    .bind(hex_u256(nonce))
    .bind(format!("{hash:#x}"))
    .bind(ROTATION_PREPARED)
    .bind(ready_at)
    .fetch_one(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("recording the cloud rotation: {error}")))?;

    Ok(CloudRotationPlan {
        rotation_id,
        safe_tx_hash: format!("{hash:#x}"),
        old_cloud_owner: hex_address(old_cloud),
        new_cloud_owner: hex_address(new_cloud),
        prev_owner: hex_address(prev),
        safe_nonce: hex_u256(nonce),
        ready_at,
    })
}

#[derive(Debug, sqlx::FromRow)]
struct CloudRotationRow {
    grant_id: String,
    old_cloud_owner: String,
    new_cloud_owner: String,
    prev_owner: String,
    safe_nonce: String,
    safe_tx_hash: String,
    status: String,
    ready_at: Option<DateTime<Utc>>,
    cancelled_at: Option<DateTime<Utc>>,
}

/// The Recovery Key's half, handed over once the day is up. The swap is rebuilt from
/// what was stored and its hash compared before anything is unsealed, so the Recovery
/// Key only ever signs the transaction this module built against a Safe that has not
/// moved since.
pub async fn cloud_rotation_signature(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    rotation_id: i64,
) -> Result<String, AccountAuthError> {
    let safe = service.safe()?;
    let vault = service.vault()?;

    let rotation = sqlx::query_as::<_, CloudRotationRow>(
        "SELECT grant_id, old_cloud_owner, new_cloud_owner, prev_owner, safe_nonce, safe_tx_hash, \
                status, ready_at, cancelled_at \
         FROM cloud_rotations WHERE id = $1 AND account_id = $2",
    )
    .bind(rotation_id)
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading the cloud rotation: {error}")))?
    .ok_or_else(|| AccountAuthError::BadRequest("no such recovery".into()))?;
    if rotation.status != ROTATION_PREPARED {
        return Err(AccountAuthError::Conflict("this recovery was already used".into()));
    }
    guard_ready(rotation.ready_at, rotation.cancelled_at)?;
    recovery::assert_grant(pool, account_id, PURPOSE_CLOUD_ROTATION, &rotation.grant_id).await?;

    let account = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no wallet".into()))?;
    let safe_address = parse_address(&account.safe_address)?;
    let old_cloud = parse_address(&rotation.old_cloud_owner)?;
    let new_cloud = parse_address(&rotation.new_cloud_owner)?;
    let prev = parse_address(&rotation.prev_owner)?;
    let nonce = parse_u256(&rotation.safe_nonce)?;
    let stored_hash: B256 = rotation
        .safe_tx_hash
        .parse()
        .map_err(|_| AccountAuthError::Internal("stored hash is corrupt".into()))?;

    if parse_address(&account.cloud_owner)? != old_cloud {
        return Err(AccountAuthError::Conflict("the cloud key changed since this recovery was started".into()));
    }
    if safe.safe_nonce(safe_address).await.map_err(chain)? != nonce {
        return Err(AccountAuthError::Conflict("the Safe moved on; start the recovery again".into()));
    }

    let data = SafeClient::swap_owner_calldata(prev, old_cloud, new_cloud);
    let hash = safe.swap_owner_hash(safe_address, &data, nonce).await.map_err(chain)?;
    if hash != stored_hash {
        return Err(AccountAuthError::Internal("the swap no longer hashes to what was prepared".into()));
    }

    let signature = recovery::sign_safe_hash(pool, vault, account_id, hash).await?;
    Ok(alloy::primitives::hex::encode_prefixed(signature))
}

/// Mark a cloud rotation done. Called by the phone after its own submission lands, so
/// the record follows the chain rather than leading it.
pub async fn settle_cloud_rotation(
    pool: &PgPool,
    service: &SmartAccounts,
    account_id: i64,
    rotation_id: i64,
) -> Result<bool, AccountAuthError> {
    let safe = service.safe()?;
    let account = row(pool, account_id)
        .await?
        .ok_or_else(|| AccountAuthError::BadRequest("this account has no wallet".into()))?;
    let safe_address = parse_address(&account.safe_address)?;

    let rotation = sqlx::query_as::<_, CloudRotationRow>(
        "SELECT grant_id, old_cloud_owner, new_cloud_owner, prev_owner, safe_nonce, safe_tx_hash, \
                status, ready_at, cancelled_at \
         FROM cloud_rotations WHERE id = $1 AND account_id = $2",
    )
    .bind(rotation_id)
    .bind(account_id)
    .fetch_optional(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading the cloud rotation: {error}")))?
    .ok_or_else(|| AccountAuthError::BadRequest("no such recovery".into()))?;
    let new_cloud = parse_address(&rotation.new_cloud_owner)?;

    // Believe the chain, not the caller: the row only moves if the Safe really has
    // the new key on it.
    let (owners, _) = safe.owners(safe_address).await.map_err(chain)?;
    if !owners.contains(&new_cloud) {
        return Ok(false);
    }

    recovery::consume_grant(pool, account_id, &rotation.grant_id).await?;
    sqlx::query("UPDATE smart_accounts SET cloud_owner = $2, updated_at = now() WHERE account_id = $1")
        .bind(account_id)
        .bind(hex_address(new_cloud))
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("recording the new cloud key: {error}")))?;
    sqlx::query("UPDATE cloud_rotations SET status = $2, executed_at = now() WHERE id = $1")
        .bind(rotation_id)
        .bind(ROTATION_EXECUTED)
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("closing the cloud rotation: {error}")))?;
    Ok(true)
}

/// Everything waiting on this account, so the app can show it and offer the stop.
pub async fn pending_recoveries(pool: &PgPool, account_id: i64) -> Result<Vec<PendingRecovery>, AccountAuthError> {
    let mut out = Vec::new();
    let devices: Vec<(i64, Option<DateTime<Utc>>, DateTime<Utc>)> = sqlx::query_as(
        "SELECT id, ready_at, created_at FROM device_rotations \
         WHERE account_id = $1 AND status = $2 AND cancelled_at IS NULL ORDER BY id",
    )
    .bind(account_id)
    .bind(ROTATION_PREPARED)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading pending recoveries: {error}")))?;
    for (id, ready_at, created_at) in devices {
        out.push(PendingRecovery { rotation_id: id, kind: "device".into(), ready_at: ready_at.unwrap_or(created_at), created_at });
    }

    let clouds: Vec<(i64, DateTime<Utc>, DateTime<Utc>)> = sqlx::query_as(
        "SELECT id, ready_at, created_at FROM cloud_rotations \
         WHERE account_id = $1 AND status = $2 AND cancelled_at IS NULL ORDER BY id",
    )
    .bind(account_id)
    .bind(ROTATION_PREPARED)
    .fetch_all(pool)
    .await
    .map_err(|error| AccountAuthError::Internal(format!("reading pending recoveries: {error}")))?;
    for (id, ready_at, created_at) in clouds {
        out.push(PendingRecovery { rotation_id: id, kind: "cloud".into(), ready_at, created_at });
    }
    Ok(out)
}

/// Stop a scheduled key change. This is the whole reason the delay exists, so it asks
/// for nothing beyond a session on the account: whoever is holding the phone and can
/// sign in is exactly the person a stolen inbox cannot impersonate.
pub async fn cancel_recovery(
    pool: &PgPool,
    account_id: i64,
    kind: &str,
    rotation_id: i64,
) -> Result<bool, AccountAuthError> {
    let table = match kind {
        "device" => "device_rotations",
        "cloud" => "cloud_rotations",
        _ => return Err(AccountAuthError::BadRequest("kind must be device or cloud".into())),
    };
    let sql = format!(
        "UPDATE {table} SET status = $3, cancelled_at = now() \
         WHERE id = $1 AND account_id = $2 AND status = $4 AND cancelled_at IS NULL"
    );
    let done = sqlx::query(&sql)
        .bind(rotation_id)
        .bind(account_id)
        .bind(ROTATION_CANCELLED)
        .bind(ROTATION_PREPARED)
        .execute(pool)
        .await
        .map_err(|error| AccountAuthError::Internal(format!("stopping the recovery: {error}")))?
        .rows_affected();
    Ok(done > 0)
}

#[cfg(test)]
mod recovery_delay_tests {
    use super::*;

    #[test]
    fn a_scheduled_change_waits_out_its_clock() {
        let later = Utc::now() + Duration::minutes(30);
        let error = guard_ready(Some(later), None).expect_err("must refuse before the clock is out");
        match error {
            AccountAuthError::Conflict(message) => assert!(message.contains("can be completed after"), "{message}"),
            other => panic!("wrong refusal: {other:?}"),
        }
    }

    #[test]
    fn a_change_whose_clock_is_out_may_run() {
        assert!(guard_ready(Some(Utc::now() - Duration::seconds(1)), None).is_ok());
    }

    #[test]
    fn a_stopped_change_never_runs_even_once_its_clock_is_out() {
        let long_past = Utc::now() - Duration::hours(48);
        let error = guard_ready(Some(long_past), Some(Utc::now())).expect_err("a stop is final");
        match error {
            AccountAuthError::Conflict(message) => assert!(message.contains("stopped"), "{message}"),
            other => panic!("wrong refusal: {other:?}"),
        }
    }

    /// Rows written before the delay existed have no ready_at. They already executed,
    /// so the guard must not turn them into something pending forever.
    #[test]
    fn old_row_without_a_clock_is_not_held_up() {
        assert!(guard_ready(None, None).is_ok());
    }

    #[test]
    fn losing_the_phone_waits_an_hour_and_losing_icloud_waits_a_day() {
        // The pair that swaps a Cloud Key needs the phone in hand, which is the harder
        // thing to steal, so it is not the one that waits longest.
        assert_eq!(DEVICE_ROTATION_DELAY, Duration::hours(1));
        assert_eq!(CLOUD_ROTATION_DELAY, Duration::hours(24));
        assert!(CLOUD_ROTATION_DELAY > DEVICE_ROTATION_DELAY);
    }

    #[tokio::test]
    async fn cancel_refuses_a_kind_it_does_not_know() {
        // The table name is chosen from a closed set rather than taken from the
        // request, which is the only reason building that SQL by hand is safe. An
        // unknown kind must be turned away before it reaches a query at all.
        let pool = PgPool::connect_lazy("postgres://unused").expect("lazy pool");
        let error = cancel_recovery(&pool, 1, "'; DROP TABLE accounts; --", 1)
            .await
            .expect_err("an unknown kind never reaches the database");
        assert!(matches!(error, AccountAuthError::BadRequest(_)));
    }
}
