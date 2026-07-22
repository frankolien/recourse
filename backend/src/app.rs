use actix_cors::Cors;
use actix_web::{web, App};
use sqlx::PgPool;

use crate::handlers;
use crate::services::apple_auth::AppleAuthService;
use crate::services::attestor::AttestorClient;
use crate::services::chain::ChainClient;
use crate::services::evidence::EvidenceStore;
use crate::services::AppConfig;

// Assembles the actix app: CORS, shared state (one web::Data per dependency), and the
// route table. main.rs stays thin; all routing lives here.
pub fn build_app(
    pool: PgPool,
    config: AppConfig,
    chain: ChainClient,
    attestor: Option<AttestorClient>,
    apple_auth: Option<AppleAuthService>,
    evidence: EvidenceStore,
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
        .wrap(Cors::permissive())
        .app_data(web::Data::new(pool))
        .app_data(web::Data::new(config))
        .app_data(web::Data::new(chain))
        .app_data(web::Data::new(attestor))
        .app_data(web::Data::new(apple_auth))
        .app_data(web::Data::new(evidence))
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
                .route("/auth/refresh", web::post().to(handlers::auth::refresh))
                .route("/auth/logout", web::post().to(handlers::auth::logout))
                .route("/me", web::get().to(handlers::auth::me))
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
                ),
        )
}
