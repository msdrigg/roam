#[test]
fn test_symbolicating_crash() {
    let crash = include_str!("./test-crash-payload.json");

    let client = symbolicate::SymbolicationClient::new();
    let result = client.symbolicate_crash(crash);

    assert!(result.is_ok(), "Symbolication failed: {:?}", result.err());
}
