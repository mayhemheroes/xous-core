// Ported from apps/vault/libraries/cbor/fuzz/fuzz_targets/fuzz_target_cbor.rs,
// updated for the current cbor API (write returns Result<(), EncoderError>).
#![no_main]
use libfuzzer_sys::fuzz_target;
use std::vec::Vec;

fuzz_target!(|data: &[u8]| {
    if let Ok(value) = cbor::read(data) {
        let mut result = Vec::new();
        assert!(cbor::write(value, &mut result).is_ok());
        assert_eq!(result, data);
    };
});
