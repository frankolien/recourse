use anyhow::{Context, Result};
use std::sync::Arc;
use webauthn_rs::prelude::*;

use crate::services::AppConfig;

// Thin wrapper over a configured webauthn-rs instance. It performs only the WebAuthn crypto
// (challenge creation and attestation/assertion verification); all persistence lives in
// account_sessions. The rp_id/rp_origin bind every ceremony to one domain, which for the
// iOS app is its apple-app-site-association webcredentials domain.
#[derive(Clone)]
pub struct PasskeyService {
    webauthn: Arc<Webauthn>,
}

impl PasskeyService {
    pub fn from_config(config: &AppConfig) -> Result<Option<Self>> {
        let (Some(rp_id), Some(rp_origin)) = (
            config.webauthn_rp_id.as_deref(),
            config.webauthn_rp_origin.as_deref(),
        ) else {
            return Ok(None);
        };
        let origin = Url::parse(rp_origin)
            .with_context(|| format!("parsing WEBAUTHN_RP_ORIGIN '{rp_origin}'"))?;
        let webauthn = WebauthnBuilder::new(rp_id, &origin)
            .context("configuring WebAuthn (check WEBAUTHN_RP_ID/ORIGIN)")?
            .build()
            .context("building WebAuthn")?;
        Ok(Some(Self {
            webauthn: Arc::new(webauthn),
        }))
    }

    pub fn start_registration(
        &self,
        user_id: Uuid,
        user_name: &str,
        display_name: &str,
        exclude: Option<Vec<CredentialID>>,
    ) -> Result<(CreationChallengeResponse, PasskeyRegistration), WebauthnError> {
        self.webauthn
            .start_passkey_registration(user_id, user_name, display_name, exclude)
    }

    pub fn finish_registration(
        &self,
        credential: &RegisterPublicKeyCredential,
        state: &PasskeyRegistration,
    ) -> Result<Passkey, WebauthnError> {
        self.webauthn.finish_passkey_registration(credential, state)
    }

    pub fn start_authentication(
        &self,
        credentials: &[Passkey],
    ) -> Result<(RequestChallengeResponse, PasskeyAuthentication), WebauthnError> {
        self.webauthn.start_passkey_authentication(credentials)
    }

    pub fn finish_authentication(
        &self,
        credential: &PublicKeyCredential,
        state: &PasskeyAuthentication,
    ) -> Result<AuthenticationResult, WebauthnError> {
        self.webauthn
            .finish_passkey_authentication(credential, state)
    }
}
