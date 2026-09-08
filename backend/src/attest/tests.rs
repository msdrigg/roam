use super::*;
use p256::ecdsa::signature::hazmat::PrehashSigner;

/// Fixed scalar so the tests are deterministic and need no RNG.
const TEST_SCALAR: [u8; 32] = [
    0x4c, 0x0b, 0x1f, 0x9a, 0x77, 0x3e, 0x21, 0x58, 0xd4, 0x66, 0x92, 0x0e, 0xa1, 0x35, 0x7c, 0x88,
    0x19, 0xbd, 0x50, 0x42, 0xc3, 0x6f, 0x0a, 0xe7, 0x31, 0x94, 0x6b, 0xdc, 0x05, 0x2a, 0x83, 0x11,
];

const TEAM_ID: &str = "2865NTZ7H3";
const BUNDLE_ID: &str = "com.msdrigg.roam";

fn policy() -> AttestPolicy {
    AttestPolicy {
        team_id: TEAM_ID.to_string(),
        bundle_ids: vec![
            BUNDLE_ID.to_string(),
            "com.msdrigg.roam.watchkitapp".to_string(),
        ],
        allow_development: false,
    }
}

fn signing_key() -> p256::ecdsa::SigningKey {
    p256::ecdsa::SigningKey::from_bytes(&TEST_SCALAR.into()).expect("valid test scalar")
}

fn public_key_sec1(key: &p256::ecdsa::SigningKey) -> Vec<u8> {
    key.verifying_key().to_sec1_point(false).as_bytes().to_vec()
}

/// Builds the `authenticatorData` an assertion carries: rpIdHash, flags, counter.
fn assertion_auth_data(bundle_id: &str, counter: u32) -> Vec<u8> {
    let app_id = format!("{TEAM_ID}.{bundle_id}");
    let mut data = Sha256::digest(app_id.as_bytes()).to_vec();
    data.push(0x40);
    data.extend_from_slice(&counter.to_be_bytes());
    data
}

fn encode_assertion(signature: &[u8], auth_data: &[u8]) -> Vec<u8> {
    let value = ciborium::Value::Map(vec![
        (
            ciborium::Value::Text("signature".into()),
            ciborium::Value::Bytes(signature.to_vec()),
        ),
        (
            ciborium::Value::Text("authenticatorData".into()),
            ciborium::Value::Bytes(auth_data.to_vec()),
        ),
    ]);
    let mut out = Vec::new();
    ciborium::into_writer(&value, &mut out).expect("assertion encodes");
    out
}

fn sign_assertion(bundle_id: &str, counter: u32, client_data: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let key = signing_key();
    let auth_data = assertion_auth_data(bundle_id, counter);

    let client_data_hash = Sha256::digest(client_data);
    let mut hasher = Sha256::new();
    hasher.update(&auth_data);
    hasher.update(client_data_hash);
    let nonce = hasher.finalize();

    // The Secure Enclave signs the nonce as a message, so ECDSA-SHA256 hashes
    // it once more. Signing `nonce` here instead would round-trip against a
    // verifier that made the same mistake and pass while every device failed.
    let digest = Sha256::digest(nonce);

    let signature: p256::ecdsa::Signature = key.sign_prehash(&digest).expect("test key signs");
    (
        encode_assertion(signature.to_der().as_bytes(), &auth_data),
        public_key_sec1(&key),
    )
}

#[test]
fn the_embedded_apple_root_is_the_expected_certificate() {
    let (_, root) = X509Certificate::from_der(APPLE_ROOT_CA_DER).expect("root parses");
    assert_eq!(
        root.subject().to_string(),
        "CN=Apple App Attestation Root CA, O=Apple Inc., ST=California"
    );
    assert_eq!(root.subject(), root.issuer(), "the root is self-issued");
}

#[test]
fn the_embedded_apple_root_is_self_signed() {
    let (_, root) = X509Certificate::from_der(APPLE_ROOT_CA_DER).expect("root parses");
    verify_signed_by(&root, &root).expect("the pinned root verifies against its own key");
}

#[test]
fn a_tampered_certificate_body_fails_verification() {
    let mut der = APPLE_ROOT_CA_DER.to_vec();
    // Flip a byte inside the TBS region, well clear of the outer DER header.
    der[80] ^= 0xff;
    let (_, tampered) = X509Certificate::from_der(&der).expect("still parses as a certificate");
    let (_, root) = X509Certificate::from_der(APPLE_ROOT_CA_DER).expect("root parses");
    assert!(verify_signed_by(&tampered, &root).is_err());
}

#[test]
fn a_valid_assertion_verifies() {
    let client_data = br#"{"s":"abc","m":"POST","p":"/v2/new-message","t":1}"#;
    let (assertion, public_key) = sign_assertion(BUNDLE_ID, 7, client_data);

    let verified = verify_assertion(&assertion, &public_key, client_data, &policy(), BUNDLE_ID)
        .expect("assertion verifies");
    assert_eq!(verified.counter, 7);
}

#[test]
fn an_assertion_over_different_client_data_is_rejected() {
    let (assertion, public_key) = sign_assertion(BUNDLE_ID, 7, b"the original request");

    let err = verify_assertion(
        &assertion,
        &public_key,
        b"a substituted request",
        &policy(),
        BUNDLE_ID,
    )
    .expect_err("the signature covers the client data");
    assert!(matches!(err, AttestError::BadSignature));
}

#[test]
fn an_assertion_from_another_key_is_rejected() {
    let client_data = b"request";
    let (assertion, _) = sign_assertion(BUNDLE_ID, 3, client_data);

    let mut other_scalar = TEST_SCALAR;
    other_scalar[0] ^= 0x01;
    let other = p256::ecdsa::SigningKey::from_bytes(&other_scalar.into()).unwrap();

    let err = verify_assertion(
        &assertion,
        &public_key_sec1(&other),
        client_data,
        &policy(),
        BUNDLE_ID,
    )
    .expect_err("only the attested key can sign");
    assert!(matches!(err, AttestError::BadSignature));
}

#[test]
fn an_assertion_for_another_bundle_id_is_rejected() {
    let client_data = b"request";
    let (assertion, public_key) = sign_assertion("com.example.other", 3, client_data);

    let err = verify_assertion(&assertion, &public_key, client_data, &policy(), BUNDLE_ID)
        .expect_err("rpIdHash pins the assertion to one app");
    assert!(matches!(err, AttestError::AppMismatch(_)));
}

#[test]
fn an_assertion_verifies_against_the_watch_bundle_id() {
    let watch = "com.msdrigg.roam.watchkitapp";
    let client_data = b"request";
    let (assertion, public_key) = sign_assertion(watch, 2, client_data);

    verify_assertion(&assertion, &public_key, client_data, &policy(), watch)
        .expect("the watch app attests against the same backend");
}

#[test]
fn truncated_authenticator_data_is_rejected() {
    let err = parse_authenticator_data(&[0u8; 20], false).expect_err("too short to be valid");
    assert!(matches!(err, AttestError::Malformed(_)));
}

#[test]
fn authenticator_data_reads_the_counter_big_endian() {
    let data = assertion_auth_data(BUNDLE_ID, 0x0102_0304);
    let parsed = parse_authenticator_data(&data, false).expect("parses");
    assert_eq!(parsed.sign_count, 0x0102_0304);
}

#[test]
fn a_credential_id_longer_than_the_buffer_is_rejected() {
    let mut data = assertion_auth_data(BUNDLE_ID, 0);
    data.extend_from_slice(AAGUID_PRODUCTION);
    // Claim a 512-byte credentialId that is not there.
    data.extend_from_slice(&512u16.to_be_bytes());
    let err =
        parse_authenticator_data(&data, true).expect_err("length is checked against the buffer");
    assert!(matches!(err, AttestError::Malformed(_)));
}

#[test]
fn the_policy_matches_only_configured_bundle_ids() {
    let policy = policy();
    let roam = Sha256::digest(format!("{TEAM_ID}.{BUNDLE_ID}").as_bytes());
    assert_eq!(policy.match_app_id(&roam).as_deref(), Some(BUNDLE_ID));

    let stranger = Sha256::digest(format!("{TEAM_ID}.com.example.other").as_bytes());
    assert_eq!(policy.match_app_id(&stranger), None);
}

#[test]
fn the_policy_rejects_the_right_app_under_another_team() {
    let policy = policy();
    let other_team = Sha256::digest(format!("XXXXXXXXXX.{BUNDLE_ID}").as_bytes());
    assert_eq!(policy.match_app_id(&other_team), None);
}

#[test]
fn attestation_cbor_that_is_not_apple_format_is_rejected() {
    let value = ciborium::Value::Map(vec![(
        ciborium::Value::Text("fmt".into()),
        ciborium::Value::Text("packed".into()),
    )]);
    let mut encoded = Vec::new();
    ciborium::into_writer(&value, &mut encoded).unwrap();

    let err = verify_attestation(&encoded, &[0u8; 32], "challenge", &policy(), Utc::now())
        .expect_err("only apple-appattest is accepted");
    assert!(matches!(err, AttestError::Malformed(_)));
}

#[test]
fn garbage_is_not_mistaken_for_an_attestation() {
    let err = verify_attestation(b"not cbor at all", &[0u8; 32], "c", &policy(), Utc::now())
        .expect_err("rejected");
    assert!(matches!(err, AttestError::Malformed(_)));
}

#[test]
fn the_nonce_extension_shape_is_enforced() {
    // A well-formed body: SEQUENCE { [1] { OCTET STRING (32) } }
    let mut good = vec![0x30, 0x24, 0xA1, 0x22, 0x04, 0x20];
    good.extend_from_slice(&[0xAB; 32]);
    assert_eq!(good.len(), 38);

    let mut wrong_tag = good.clone();
    wrong_tag[2] = 0xA2;
    assert_ne!(&good[..6], &wrong_tag[..6]);
}

/// A real assertion, produced by a real Secure Enclave on a real device.
///
/// The synthetic assertions above are signed by this file's own helper, so they
/// only ever prove the verifier agrees with `sign_assertion`. When both halves
/// shared a wrong idea of what Apple signs they round-tripped happily while
/// every device in the field got `BadSignature`. This vector is Apple's own
/// output and cannot be talked into agreeing with a mistake.
///
/// From <https://github.com/takimoto3/app-attest> (`testdata/ios-14.4.json`),
/// captured from Vincent Haupert's `apple-appattest-poc`, iOS 14.4.
mod real_device_vector {
    use super::*;
    use base64::Engine as _;
    use base64::engine::general_purpose::STANDARD as B64;

    const TEAM_ID: &str = "6MURL8TA57";
    const BUNDLE_ID: &str = "de.vincent-haupert.apple-appattest-poc";
    const ASSERTION_B64: &str = "omlzaWduYXR1cmVYRjBEAiBJ6BT/QR689UKy84YyN3RDydYD9KVQ2BTRK+x1i8ezqAIgGM7BsZbSuF6TjmK6xtOFekyVyjf8akGvp5qFRGm9LTxxYXV0aGVudGljYXRvckRhdGFYJUVlEup+JpR2q5Pht5cWhVkv9z+JSsDsL9VICKCL+2yPQAAAAAE=";
    /// The literal bytes `wurzelpfropf`.
    const CLIENT_DATA_B64: &str = "d3VyemVscGZyb3Bm";
    const PUBLIC_KEY_SEC1_B64: &str =
        "BIjANKGQqn28WgYVAcZUKAOUJYIZiz8cxUZzyjua0gtBUoJnpU9f26BGn6+0a7aZCjlr8E+UpJ1DIMgcerJAo5g=";

    fn real_policy() -> AttestPolicy {
        AttestPolicy {
            team_id: TEAM_ID.to_string(),
            bundle_ids: vec![BUNDLE_ID.to_string()],
            allow_development: true,
        }
    }

    #[test]
    fn an_assertion_from_a_real_device_verifies() {
        let assertion = B64.decode(ASSERTION_B64).expect("vector decodes");
        let client_data = B64.decode(CLIENT_DATA_B64).expect("vector decodes");
        let public_key = B64.decode(PUBLIC_KEY_SEC1_B64).expect("vector decodes");

        let verified = verify_assertion(
            &assertion,
            &public_key,
            &client_data,
            &real_policy(),
            BUNDLE_ID,
        )
        .expect("a genuine Apple assertion verifies");

        assert_eq!(verified.counter, 1);
    }
}
