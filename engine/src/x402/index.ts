export {
  X402_VERSION,
  ARC_TESTNET_CAIP2,
  RECOURSE_SCHEME,
  X402Error,
  type ResourceInfo,
  type PaymentRequirements,
  type PaymentRequired,
  type PaymentPayload,
  type SettlementResponse,
  type Extension,
  type Extensions,
} from "./types";

export {
  PAYMENT_REQUIRED_HEADER,
  PAYMENT_SIGNATURE_HEADER,
  PAYMENT_RESPONSE_HEADER,
  encodePaymentRequired,
  encodePaymentPayload,
  encodeSettlementResponse,
  decodePaymentRequired,
  decodePaymentPayload,
  decodeSettlementResponse,
  readHeader,
} from "./headers";

export {
  RECOURSE_EXTENSION_ID,
  RECOURSE_EXTENSION_SCHEMA,
  buildRecourseExtension,
  readRecourseExtension,
  echoExtensions,
  assertExtensionsEchoed,
  type RecourseExtensionInfo,
} from "./extension";

export {
  authorizationNonce,
  parseRecourseEscrowPayload,
  type EscrowAuthorization,
  type RecourseEscrowPayload,
} from "./scheme";

export {
  EscrowStatus,
  quote,
  quoteHeader,
  verify,
  type EscrowPayment,
  type EscrowReader,
  type QuoteOptions,
  type VerifyResult,
} from "./gateway";

export {
  parseQuote,
  assessProtection,
  verifyTerms,
  authorizationMessage,
  buildPayment,
  buildPaymentHeader,
  type Quote,
  type ClaimOutlook,
  type ProtectionAssessment,
  type AgreementReader,
  type TermsCheck,
} from "./client";
