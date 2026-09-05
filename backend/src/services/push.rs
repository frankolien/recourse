//! Alerts to phones through APNs.
//!
//! Token-based auth: one ES256 JWT signed with the team's .p8 key, reused for most
//! of the hour Apple allows. Every send is best effort and logged; nothing that
//! moves money waits on a notification.

use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::Serialize;
use serde_json::{json, Value};
use sqlx::PgPool;

use super::AppConfig as Config;

const TOKEN_LIFETIME: Duration = Duration::from_secs(50 * 60);

pub struct Push {
    client: reqwest::Client,
    key: EncodingKey,
    key_id: String,
    team_id: String,
    bundle_id: String,
    jwt: Mutex<Option<(String, Instant)>>,
}

#[derive(Serialize)]
struct Claims {
    iss: String,
    iat: u64,
}

/// A device row, with the environment its token belongs to.
#[derive(sqlx::FromRow)]
struct Device {
    token: String,
    environment: String,
}

impl Push {
    /// None when any of the four settings is missing; the app then simply never pushes.
    pub fn from_config(config: &Config) -> Option<Push> {
        let (Some(key_id), Some(team_id), Some(pem), Some(bundle_id)) = (
            config.apns_key_id.clone(),
            config.apns_team_id.clone(),
            config.apns_key_p8.clone(),
            config.apns_bundle_id.clone(),
        ) else {
            return None;
        };
        // Railway stores the key on one line; the PEM parser wants real newlines.
        let pem = pem.replace("\\n", "\n");
        let key = match EncodingKey::from_ec_pem(pem.as_bytes()) {
            Ok(key) => key,
            Err(error) => {
                tracing::error!("APNS_KEY_P8 is not a usable EC key: {error}");
                return None;
            }
        };
        Some(Push { client: reqwest::Client::new(), key, key_id, team_id, bundle_id, jwt: Mutex::new(None) })
    }

    fn bearer(&self) -> Result<String, jsonwebtoken::errors::Error> {
        if let Ok(slot) = self.jwt.lock() {
            if let Some((token, made)) = slot.as_ref() {
                if made.elapsed() < TOKEN_LIFETIME {
                    return Ok(token.clone());
                }
            }
        }
        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(self.key_id.clone());
        let iat = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        let token = jsonwebtoken::encode(&header, &Claims { iss: self.team_id.clone(), iat }, &self.key)?;
        if let Ok(mut slot) = self.jwt.lock() {
            *slot = Some((token.clone(), Instant::now()));
        }
        Ok(token)
    }

    /// One alert to every phone of every account named. `route` rides along so a tap
    /// opens the right screen.
    pub async fn notify(&self, pool: &PgPool, account_ids: &[i64], title: &str, body: &str, route: Value) {
        if account_ids.is_empty() {
            return;
        }
        let devices: Vec<Device> = match sqlx::query_as("SELECT token, environment FROM push_devices WHERE account_id = ANY($1)")
            .bind(account_ids)
            .fetch_all(pool)
            .await
        {
            Ok(rows) => rows,
            Err(error) => {
                tracing::warn!("push: reading devices: {error}");
                return;
            }
        };
        if devices.is_empty() {
            tracing::info!("push: no devices for accounts {account_ids:?}; nothing sent for {title:?}");
            return;
        }
        tracing::info!("push: {} device(s) across {} account(s) for {title:?}", devices.len(), account_ids.len());
        let bearer = match self.bearer() {
            Ok(token) => token,
            Err(error) => {
                tracing::error!("push: signing the APNs token: {error}");
                return;
            }
        };
        let payload = json!({
            "aps": { "alert": { "title": title, "body": body }, "sound": "default" },
            "route": route,
        });
        for device in devices {
            let host = if device.environment == "sandbox" { "api.sandbox.push.apple.com" } else { "api.push.apple.com" };
            let url = format!("https://{host}/3/device/{}", device.token);
            let sent = self
                .client
                .post(&url)
                .bearer_auth(&bearer)
                .header("apns-topic", &self.bundle_id)
                .header("apns-push-type", "alert")
                .header("apns-priority", "10")
                .json(&payload)
                .send()
                .await;
            match sent {
                Ok(response) if response.status().is_success() => tracing::info!("push: delivered to a {} device", device.environment),
                Ok(response) => {
                    let status = response.status();
                    let text = response.text().await.unwrap_or_default();
                    tracing::warn!("push: APNs refused a token: {status} {text}");
                    // A token Apple no longer knows is gone for good.
                    if status.as_u16() == 410 || text.contains("BadDeviceToken") || text.contains("Unregistered") {
                        let _ = sqlx::query("DELETE FROM push_devices WHERE token = $1").bind(&device.token).execute(pool).await;
                    }
                }
                Err(error) => tracing::warn!("push: sending to APNs: {error}"),
            }
        }
    }
}

/// The accounts that sign for a treasury from a phone: Recourse accounts whose Safe
/// is a member, plus wallet members that signed into the console with an account.
pub async fn member_accounts(pool: &PgPool, olien_id: i64, except: Option<i64>) -> Vec<i64> {
    let rows: Result<Vec<(i64,)>, sqlx::Error> = sqlx::query_as(
        "SELECT DISTINCT a.account_id FROM (
            SELECT sa.account_id FROM olien_signers s
              JOIN smart_accounts sa ON lower(sa.safe_address) = lower(s.address) AND sa.status = 'live'
             WHERE s.olien_id = $1 AND s.status = 'active' AND s.address IS NOT NULL
            UNION
            SELECT l.account_id FROM olien_signers s
              JOIN treasury_linked_addresses l ON lower(l.address) = lower(s.address)
             WHERE s.olien_id = $1 AND s.status = 'active' AND s.address IS NOT NULL
         ) a WHERE $2::bigint IS NULL OR a.account_id <> $2",
    )
    .bind(olien_id)
    .bind(except)
    .fetch_all(pool)
    .await;
    match rows {
        Ok(rows) => rows.into_iter().map(|(id,)| id).collect(),
        Err(error) => {
            tracing::warn!("push: reading members: {error}");
            Vec::new()
        }
    }
}
