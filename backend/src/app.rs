use actix_cors::Cors;
use actix_web::http::header::{self, HeaderName};
use actix_web::{web, App};
use sqlx::PgPool;

// Build the CORS layer. With no configured origins we fall back to permissive so local
// dev and the demo just work; in production CORS_ALLOWED_ORIGINS locks it to the web app.
fn build_cors(origins: &[String]) -> Cors {
    if origins.is_empty() {
        return Cors::permissive();
    }
    let mut cors = Cors::default()
        .allowed_methods(vec!["GET", "POST", "PUT", "OPTIONS"])
        .allowed_headers(vec![
            header::CONTENT_TYPE,
            header::AUTHORIZATION,
            HeaderName::from_static("x-recourse-auth"),
        ])
        .max_age(3600);
    for origin in origins {
        cors = cors.allowed_origin(origin);
    }
    cors
}

use crate::handlers;
use crate::services::apple_auth::AppleAuthService;
use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use crate::services::cloudinary::Cloudinary;
use crate::services::evidence::EvidenceStore;
use crate::services::google_auth::GoogleAuthService;
use crate::services::orders::OrderStore;
use crate::services::passkey::PasskeyService;
use crate::services::AppConfig;

// Assembles the actix app: CORS, shared state (one web::Data per dependency), and the
// route table. main.rs stays thin; all routing lives here. The dependencies are injected
// one web::Data each, hence the argument count.
#[allow(clippy::too_many_arguments)]
pub fn build_app(
    pool: PgPool,
    config: AppConfig,
    chain: ChainClient,
    attestor: Option<AttestorClient>,
    apple_auth: Option<AppleAuthService>,
    google_auth: Option<GoogleAuthService>,
    passkey: Option<PasskeyService>,
    evidence: EvidenceStore,
    orders: OrderStore,
    cloudinary: Option<Cloudinary>,
) -> App<
    impl actix_web::dev::ServiceFactory<
        actix_web::dev::ServiceRequest,
        Config = (),
        Response = actix_web::dev::ServiceResponse<impl actix_web::body::MessageBody>,
        Error = actix_web::Error,
        InitError = (),
    >,
> {
    App::new()
        .wrap(build_cors(&config.cors_allowed_origins))
        .app_data(web::Data::new(pool))
        .app_data(web::Data::new(config))
        .app_data(web::Data::new(chain))
        .app_data(web::Data::new(attestor))
        .app_data(web::Data::new(apple_auth))
        .app_data(web::Data::new(google_auth))
        .app_data(web::Data::new(passkey))
        .app_data(web::Data::new(evidence))
        .app_data(web::Data::new(orders))
        .app_data(web::Data::new(cloudinary))
        .route("/health", web::get().to(handlers::health::health_check))
        .service(
            web::scope("/api")
                .route(
                    "/payments",
                    web::get().to(handlers::payments::list_payments),
                )
                .route(
                    "/payments/{id}",
                    web::get().to(handlers::payments::get_payment),
                )
                .route(
                    "/payments/{id}/evidence",
                    web::get().to(handlers::evidence::get_payment_evidence),
                )
                .route(
                    "/disputes",
                    web::get().to(handlers::disputes::list_disputes),
                )
                .route(
                    "/policies",
                    web::get().to(handlers::policies::list_policies),
                )
                .route(
                    "/policies/{id}",
                    web::get().to(handlers::policies::get_policy),
                )
                .route("/demo/attest", web::post().to(handlers::demo::attest))
                .route("/demo/resolve", web::post().to(handlers::demo::resolve))
                // Issue a one-time nonce for wallet-signature auth on write routes.
                .route("/auth/challenge", web::post().to(handlers::auth::challenge))
                .route(
                    "/auth/apple/challenge",
                    web::post().to(handlers::auth::apple_challenge),
                )
                .route(
                    "/auth/apple",
                    web::post().to(handlers::auth::apple_exchange),
                )
                .route(
                    "/auth/google",
                    web::post().to(handlers::auth::google_exchange),
                )
                .route(
                    "/auth/email/register",
                    web::post().to(handlers::auth::email_register),
                )
                .route(
                    "/auth/email/login",
                    web::post().to(handlers::auth::email_login),
                )
                .route(
                    "/auth/passkey/register/start",
                    web::post().to(handlers::auth::passkey_register_start),
                )
                .route(
                    "/auth/passkey/register/finish",
                    web::post().to(handlers::auth::passkey_register_finish),
                )
                .route(
                    "/auth/passkey/login/start",
                    web::post().to(handlers::auth::passkey_login_start),
                )
                .route(
                    "/auth/passkey/login/finish",
                    web::post().to(handlers::auth::passkey_login_finish),
                )
                .route("/auth/refresh", web::post().to(handlers::auth::refresh))
                .route("/auth/logout", web::post().to(handlers::auth::logout))
                .route("/me", web::get().to(handlers::auth::me))
                // Cheques. The rows carry no authority: a cheque is not bearer, so
                // this is delivery rather than custody of anything.
                // An invoice is a request for a cheque: the issuer fixes the terms,
                // the payer answers with a signature over exactly those terms.
                .route("/invoices", web::post().to(handlers::invoices::issue))
                .route("/invoices/inbox", web::get().to(handlers::invoices::inbox))
                .route("/invoices/outbox", web::get().to(handlers::invoices::outbox))
                .route(
                    "/invoices/{id}/sign",
                    web::post().to(handlers::invoices::sign),
                )
                .route(
                    "/invoices/{id}/cancel",
                    web::post().to(handlers::invoices::cancel),
                )
                .route("/cheques", web::post().to(handlers::cheques::write_cheque))
                .route("/cheques/inbox", web::get().to(handlers::cheques::inbox))
                .route("/cheques/outbox", web::get().to(handlers::cheques::outbox))
                // Naming someone instead of addressing them. Resolution is public
                // because a sender need not be a Recourse user; claiming is not.
                .route("/handles/names", web::post().to(handlers::handles::names))
                .route(
                    "/handles/{handle}",
                    web::get().to(handlers::handles::resolve_handle),
                )
                .route("/me/handle", web::get().to(handlers::handles::my_handle))
                .route("/me/handle", web::put().to(handlers::handles::claim_handle))
                // The wallet key, sealed by the device. The server stores ciphertext
                // and holds no PIN, so these routes are storage rather than custody.
                .route(
                    "/me/wallet-backup",
                    web::get().to(handlers::wallet_backup::get_backup),
                )
                .route(
                    "/me/wallet-backup",
                    web::put().to(handlers::wallet_backup::put_backup),
                )
                .route(
                    "/me/wallet-backup",
                    web::delete().to(handlers::wallet_backup::delete_backup),
                )
                .route("/me/profile", web::put().to(handlers::auth::update_profile))
                // Verify + record a payment's evidence list against the onchain root.
                .route(
                    "/evidence/manifest",
                    web::post().to(handlers::evidence::verify_manifest),
                )
                // Evidence uploads (photos) exceed the default 256 KB body cap.
                .service(
                    web::resource("/evidence")
                        .app_data(web::PayloadConfig::new(10 * 1024 * 1024))
                        .route(web::post().to(handlers::evidence::put_evidence)),
                )
                .route(
                    "/evidence/{hash}",
                    web::get().to(handlers::evidence::get_evidence),
                )
                // Merchant order manifests: exact bytes in, keccak256 = orderRef out.
                .service(
                    web::resource("/orders")
                        .app_data(web::PayloadConfig::new(32 * 1024))
                        .route(web::post().to(handlers::orders::put_manifest)),
                )
                // Product images exceed the default 256 KB body cap; the app compresses
                // before upload, this is the hard server-side ceiling.
                .service(
                    web::resource("/orders/image")
                        .app_data(web::PayloadConfig::new(5 * 1024 * 1024))
                        .route(web::post().to(handlers::orders::put_image)),
                )
                // HEAD is registered too: link-preview bots probe images with HEAD
                // before fetching, and actix does not match HEAD to GET routes.
                .route(
                    "/orders/image/{hash}",
                    web::get().to(handlers::orders::get_image),
                )
                .route(
                    "/orders/image/{hash}",
                    web::head().to(handlers::orders::get_image),
                )
                .route(
                    "/orders/{order_ref}",
                    web::get().to(handlers::orders::get_manifest),
                ),
        )
}
