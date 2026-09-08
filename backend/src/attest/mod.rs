//! App Attest verification.
//!
//! Implements the server half of Apple's "Validating Apps That Connect to Your
//! Server": the one-time attestation that binds a Secure Enclave key to a
//! genuine copy of the app, and the per-request assertion that proves the same
//! key signed this request.
//!
//! The wire formats here are Apple's and are not self-describing, so the layout
//! of `authenticatorData` and of the credCert nonce extension are spelled out
//! at the point they are parsed.

use chrono::{DateTime, Utc};
use p256::ecdsa::signature::hazmat::PrehashVerifier;
use sha2::{Digest, Sha256, Sha384};
use x509_parser::prelude::*;

mod receipt;
pub use receipt::{ReceiptError, VerifiedReceipt, verify_receipt};

mod replay;
pub use replay::ReplayWindow;

#[cfg(test)]
mod tests;

/// Apple App Attestation Root CA, fetched from
/// <https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem>.
/// P-384, valid to 2045.
pub(crate) const APPLE_ROOT_CA_DER: &[u8] = include_bytes!("apple_app_attest_root_ca.der");

/// credCert extension carrying the attestation nonce.
const NONCE_EXTENSION_OID: &str = "1.2.840.113635.100.8.2";

const OID_ECDSA_SHA256: &str = "1.2.840.10045.4.3.2";
const OID_ECDSA_SHA384: &str = "1.2.840.10045.4.3.3";

/// An attested key comes from either the development or production App Attest
/// environment, distinguished only by the aaguid in `authenticatorData`. A
/// development key means a build signed with a development profile, so
/// production must refuse it or the attestation proves nothing.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Environment {
    Production,
    Development,
}

impl Environment {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Production => "production",
            Self::Development => "development",
        }
    }
}

const AAGUID_PRODUCTION: &[u8; 16] = b"appattest\0\0\0\0\0\0\0";
const AAGUID_DEVELOPMENT: &[u8; 16] = b"appattestdevelop";

#[derive(Debug, thiserror::Error)]
pub enum AttestError {
    #[error("malformed attestation object: {0}")]
    Malformed(String),
    #[error("certificate chain rejected: {0}")]
    Chain(String),
    #[error("attestation does not match the expected app: {0}")]
    AppMismatch(String),
    #[error("attestation nonce mismatch")]
    NonceMismatch,
    #[error("key identifier does not match the attested public key")]
    KeyIdMismatch,
    #[error("{0} environment attestation is not accepted here")]
    EnvironmentRejected(&'static str),
    #[error("assertion signature is not valid")]
    BadSignature,
    #[error("assertion counter {counter} was already used (window high-water {high_water})")]
    ReplayedCounter { counter: u32, high_water: u32 },
}

/// What the server expects every attestation to claim.
#[derive(Debug, Clone)]
pub struct AttestPolicy {
    pub team_id: String,
    /// Every bundle id allowed to register, so the watch app and the phone app
    /// can attest against the same backend.
    pub bundle_ids: Vec<String>,
    pub allow_development: bool,
}

impl AttestPolicy {
    /// `rpIdHash` is `SHA256("<teamId>.<bundleId>")`. Matching by hash means the
    /// bundle id is recovered by trying each allowed one rather than read out of
    /// the attestation.
    fn match_app_id(&self, rp_id_hash: &[u8]) -> Option<String> {
        self.bundle_ids.iter().find_map(|bundle_id| {
            let app_id = format!("{}.{}", self.team_id, bundle_id);
            (Sha256::digest(app_id.as_bytes()).as_slice() == rp_id_hash).then(|| bundle_id.clone())
        })
    }
}

#[derive(Debug, Clone)]
pub struct VerifiedAttestation {
    pub key_id: Vec<u8>,
    /// Uncompressed SEC1 point, the form `p256::ecdsa::VerifyingKey` reads back.
    pub public_key: Vec<u8>,
    pub bundle_id: String,
    pub environment: Environment,
    pub receipt: Vec<u8>,
}

/// `authenticatorData` is a packed big-endian record with no length prefix:
///
/// ```text
/// 32  rpIdHash
///  1  flags
///  4  signCount
/// 16  aaguid                  (attestation only)
///  2  credentialIdLength      (attestation only)
///  N  credentialId            (attestation only)
/// ```
#[derive(Debug)]
struct AuthenticatorData<'a> {
    rp_id_hash: &'a [u8],
    sign_count: u32,
    aaguid: Option<&'a [u8]>,
    credential_id: Option<&'a [u8]>,
}

fn parse_authenticator_data(
    data: &[u8],
    with_credential: bool,
) -> Result<AuthenticatorData<'_>, AttestError> {
    if data.len() < 37 {
        return Err(AttestError::Malformed(format!(
            "authenticatorData is {} bytes, expected at least 37",
            data.len()
        )));
    }
    let rp_id_hash = &data[0..32];
    let sign_count = u32::from_be_bytes([data[33], data[34], data[35], data[36]]);

    if !with_credential {
        return Ok(AuthenticatorData {
            rp_id_hash,
            sign_count,
            aaguid: None,
            credential_id: None,
        });
    }

    if data.len() < 55 {
        return Err(AttestError::Malformed(format!(
            "authenticatorData is {} bytes, too short to carry attested credential data",
            data.len()
        )));
    }
    let aaguid = &data[37..53];
    let cred_len = u16::from_be_bytes([data[53], data[54]]) as usize;
    let cred_end = 55 + cred_len;
    if data.len() < cred_end {
        return Err(AttestError::Malformed(format!(
            "credentialId claims {cred_len} bytes but only {} remain",
            data.len() - 55
        )));
    }

    Ok(AuthenticatorData {
        rp_id_hash,
        sign_count,
        aaguid: Some(aaguid),
        credential_id: Some(&data[55..cred_end]),
    })
}

fn cbor_bytes(value: &ciborium::Value, field: &str) -> Result<Vec<u8>, AttestError> {
    value
        .as_bytes()
        .cloned()
        .ok_or_else(|| AttestError::Malformed(format!("{field} is not a byte string")))
}

fn cbor_field<'a>(
    map: &'a [(ciborium::Value, ciborium::Value)],
    key: &str,
) -> Result<&'a ciborium::Value, AttestError> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .map(|(_, v)| v)
        .ok_or_else(|| AttestError::Malformed(format!("attestation object has no `{key}`")))
}

/// Verifies a fresh attestation and returns the credential to store.
///
/// `challenge` is the exact string handed out by `/v3/attest/challenge`; the
/// client hashes its UTF-8 bytes to form `clientDataHash`, so both sides work
/// from the string and never have to agree on a binary encoding.
pub fn verify_attestation(
    attestation: &[u8],
    expected_key_id: &[u8],
    challenge: &str,
    policy: &AttestPolicy,
    now: DateTime<Utc>,
) -> Result<VerifiedAttestation, AttestError> {
    let value: ciborium::Value = ciborium::from_reader(attestation)
        .map_err(|e| AttestError::Malformed(format!("attestation is not valid CBOR: {e}")))?;
    let map = value
        .as_map()
        .ok_or_else(|| AttestError::Malformed("attestation object is not a CBOR map".into()))?;

    match cbor_field(map, "fmt")?.as_text() {
        Some("apple-appattest") => {}
        other => {
            return Err(AttestError::Malformed(format!(
                "unexpected attestation format {other:?}"
            )));
        }
    }

    let auth_data_raw = cbor_bytes(cbor_field(map, "authData")?, "authData")?;
    let att_stmt = cbor_field(map, "attStmt")?
        .as_map()
        .ok_or_else(|| AttestError::Malformed("attStmt is not a CBOR map".into()))?;

    let x5c = cbor_field(att_stmt, "x5c")?
        .as_array()
        .ok_or_else(|| AttestError::Malformed("x5c is not a CBOR array".into()))?;
    if x5c.len() != 2 {
        return Err(AttestError::Malformed(format!(
            "x5c holds {} certificates, expected the credCert and one intermediate",
            x5c.len()
        )));
    }
    let cred_cert_der = cbor_bytes(&x5c[0], "x5c[0]")?;
    let intermediate_der = cbor_bytes(&x5c[1], "x5c[1]")?;
    let receipt = cbor_bytes(cbor_field(att_stmt, "receipt")?, "receipt")?;

    let cred_cert = verify_chain(&cred_cert_der, &intermediate_der, now)?;

    // nonce = SHA256(authData || SHA256(challenge)), which the credCert commits
    // to in its Apple-private extension. This is what makes the attestation
    // answer *this* challenge rather than a replayed one.
    let client_data_hash = Sha256::digest(challenge.as_bytes());
    let mut hasher = Sha256::new();
    hasher.update(&auth_data_raw);
    hasher.update(client_data_hash);
    let expected_nonce = hasher.finalize();

    let cert_nonce = credcert_nonce(&cred_cert)?;
    if cert_nonce != expected_nonce.as_slice() {
        return Err(AttestError::NonceMismatch);
    }

    let public_key = cred_cert.public_key().subject_public_key.data.to_vec();
    // The key identifier the client sends is the SHA256 of the attested public
    // key, which is also how the credential is addressed on every later request.
    let derived_key_id = Sha256::digest(&public_key);
    if derived_key_id.as_slice() != expected_key_id {
        return Err(AttestError::KeyIdMismatch);
    }

    let auth_data = parse_authenticator_data(&auth_data_raw, true)?;

    let bundle_id = policy
        .match_app_id(auth_data.rp_id_hash)
        .ok_or_else(|| AttestError::AppMismatch("rpIdHash matches no allowed bundle id".into()))?;

    if auth_data.sign_count != 0 {
        return Err(AttestError::Malformed(format!(
            "fresh attestation carries signCount {}, expected 0",
            auth_data.sign_count
        )));
    }

    let aaguid = auth_data
        .aaguid
        .ok_or_else(|| AttestError::Malformed("attestation carries no aaguid".into()))?;
    let environment = if aaguid == AAGUID_PRODUCTION {
        Environment::Production
    } else if aaguid == AAGUID_DEVELOPMENT {
        Environment::Development
    } else {
        return Err(AttestError::Malformed(format!(
            "unrecognised aaguid {}",
            hex(aaguid)
        )));
    };
    if environment == Environment::Development && !policy.allow_development {
        return Err(AttestError::EnvironmentRejected("development"));
    }

    match auth_data.credential_id {
        Some(id) if id == derived_key_id.as_slice() => {}
        Some(_) => return Err(AttestError::KeyIdMismatch),
        None => {
            return Err(AttestError::Malformed(
                "attestation carries no credentialId".into(),
            ));
        }
    }

    Ok(VerifiedAttestation {
        key_id: derived_key_id.to_vec(),
        public_key,
        bundle_id,
        environment,
        receipt,
    })
}

/// Outcome of a valid assertion: the counter to fold into the stored replay
/// window, and the client data the caller still has to interpret.
#[derive(Debug, Clone)]
pub struct VerifiedAssertion {
    pub counter: u32,
}

/// Verifies that `assertion` was produced by `public_key` over `client_data`.
///
/// Apple's step 2 forms `nonce = SHA256(authenticatorData || SHA256(clientData))`,
/// and step 3 asks for a signature that "is valid for nonce" -- nonce as the
/// *message*, not as a digest. ECDSA-SHA256 hashes the message it is given, so
/// the value actually signed is `SHA256(nonce)`, and the prehash verifier below
/// has to be handed that second hash. Verifying against `nonce` itself fails
/// every real assertion the Secure Enclave produces.
pub fn verify_assertion(
    assertion: &[u8],
    public_key: &[u8],
    client_data: &[u8],
    policy: &AttestPolicy,
    bundle_id: &str,
) -> Result<VerifiedAssertion, AttestError> {
    let value: ciborium::Value = ciborium::from_reader(assertion)
        .map_err(|e| AttestError::Malformed(format!("assertion is not valid CBOR: {e}")))?;
    let map = value
        .as_map()
        .ok_or_else(|| AttestError::Malformed("assertion is not a CBOR map".into()))?;

    let signature_der = cbor_bytes(cbor_field(map, "signature")?, "signature")?;
    let auth_data_raw = cbor_bytes(cbor_field(map, "authenticatorData")?, "authenticatorData")?;

    let auth_data = parse_authenticator_data(&auth_data_raw, false)?;

    let app_id = format!("{}.{}", policy.team_id, bundle_id);
    if Sha256::digest(app_id.as_bytes()).as_slice() != auth_data.rp_id_hash {
        return Err(AttestError::AppMismatch(
            "assertion rpIdHash does not match the registered bundle id".into(),
        ));
    }

    let client_data_hash = Sha256::digest(client_data);
    let mut hasher = Sha256::new();
    hasher.update(&auth_data_raw);
    hasher.update(client_data_hash);
    let nonce = hasher.finalize();
    let digest = Sha256::digest(nonce);

    let verifying_key = p256::ecdsa::VerifyingKey::from_sec1_bytes(public_key)
        .map_err(|_| AttestError::Malformed("stored public key is not a P-256 point".into()))?;
    let signature =
        p256::ecdsa::Signature::from_der(&signature_der).map_err(|_| AttestError::BadSignature)?;
    verifying_key
        .verify_prehash(&digest, &signature)
        .map_err(|_| AttestError::BadSignature)?;

    Ok(VerifiedAssertion {
        counter: auth_data.sign_count,
    })
}

/// Reads the attestation nonce out of the credCert's Apple extension.
///
/// The extension body is a fixed DER shape that Apple never varies:
/// `SEQUENCE { [1] { OCTET STRING (32) } }`, so it is matched literally rather
/// than parsed generically.
fn credcert_nonce(cert: &X509Certificate<'_>) -> Result<Vec<u8>, AttestError> {
    let extension = cert
        .extensions()
        .iter()
        .find(|ext| ext.oid.to_id_string() == NONCE_EXTENSION_OID)
        .ok_or_else(|| AttestError::Malformed("credCert carries no attestation nonce".into()))?;

    let v = extension.value;
    if v.len() != 38
        || v[0] != 0x30
        || v[1] != 0x24
        || v[2] != 0xA1
        || v[3] != 0x22
        || v[4] != 0x04
        || v[5] != 0x20
    {
        return Err(AttestError::Malformed(
            "attestation nonce extension has an unexpected DER shape".into(),
        ));
    }
    Ok(v[6..38].to_vec())
}

/// Walks credCert -> intermediate -> the pinned Apple root.
///
/// The chain is verified by hand rather than through a TLS path builder: these
/// are not server certificates, they carry no DNS names and no server-auth EKU,
/// so every general-purpose verifier rejects them for the wrong reason.
fn verify_chain<'a>(
    cred_cert_der: &'a [u8],
    intermediate_der: &[u8],
    now: DateTime<Utc>,
) -> Result<X509Certificate<'a>, AttestError> {
    let (_, root) = X509Certificate::from_der(APPLE_ROOT_CA_DER)
        .map_err(|e| AttestError::Chain(format!("embedded Apple root is unreadable: {e}")))?;
    let (_, intermediate) = X509Certificate::from_der(intermediate_der)
        .map_err(|e| AttestError::Chain(format!("intermediate is not a certificate: {e}")))?;
    let (_, cred_cert) = X509Certificate::from_der(cred_cert_der)
        .map_err(|e| AttestError::Chain(format!("credCert is not a certificate: {e}")))?;

    for (label, cert) in [("intermediate", &intermediate), ("credCert", &cred_cert)] {
        let not_before = cert.validity().not_before.timestamp();
        let not_after = cert.validity().not_after.timestamp();
        let now_ts = now.timestamp();
        if now_ts < not_before || now_ts > not_after {
            return Err(AttestError::Chain(format!(
                "{label} is outside its validity window"
            )));
        }
    }

    verify_signed_by(&intermediate, &root).map_err(|e| {
        AttestError::Chain(format!("intermediate is not signed by the Apple root: {e}"))
    })?;
    verify_signed_by(&cred_cert, &intermediate).map_err(|e| {
        AttestError::Chain(format!("credCert is not signed by the intermediate: {e}"))
    })?;

    Ok(cred_cert)
}

/// Checks `cert`'s signature against `issuer`'s public key.
///
/// The digest comes from the certificate's own signature algorithm rather than
/// the issuer's curve: Apple's intermediate is P-384 but signs each credCert
/// with SHA-256, so assuming the curve's matching digest fails on real chains.
fn verify_signed_by(
    cert: &X509Certificate<'_>,
    issuer: &X509Certificate<'_>,
) -> Result<(), String> {
    let tbs = cert.tbs_certificate.as_ref();
    let signature = cert.signature_value.data.as_ref();
    let issuer_key = issuer.public_key().subject_public_key.data.as_ref();

    let algorithm = cert.signature_algorithm.algorithm.to_id_string();
    let digest: Vec<u8> = match algorithm.as_str() {
        OID_ECDSA_SHA256 => Sha256::digest(tbs).to_vec(),
        OID_ECDSA_SHA384 => Sha384::digest(tbs).to_vec(),
        other => return Err(format!("unsupported signature algorithm {other}")),
    };

    // Both Apple CA certificates are P-384; only the leaf key is P-256.
    if let Ok(key) = p384::ecdsa::VerifyingKey::from_sec1_bytes(issuer_key) {
        let sig = p384::ecdsa::Signature::from_der(signature)
            .map_err(|e| format!("signature is not DER ECDSA: {e}"))?;
        return key
            .verify_prehash(&digest, &sig)
            .map_err(|_| "signature does not verify".to_string());
    }
    let key = p256::ecdsa::VerifyingKey::from_sec1_bytes(issuer_key)
        .map_err(|e| format!("issuer key is neither P-384 nor P-256: {e}"))?;
    let sig = p256::ecdsa::Signature::from_der(signature)
        .map_err(|e| format!("signature is not DER ECDSA: {e}"))?;
    key.verify_prehash(&digest, &sig)
        .map_err(|_| "signature does not verify".to_string())
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
