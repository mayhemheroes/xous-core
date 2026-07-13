#!/usr/bin/env bash
#
# mayhem/build.sh — build xous-core's two upstream cargo-fuzz targets as sanitized
# libFuzzer binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), then
# pre-build the fuzzed crates' upstream test suites so mayhem/test.sh only RUNS them.
#
# Runs inside the commit image (RUST mayhem/Dockerfile) as `mayhem` in /mayhem.
# The Rust toolchain + cargo registry live at $CARGO_HOME=/opt/toolchains/rust/cargo.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): the PATCH tier re-runs THIS script OFFLINE.
# This first (online) build populates the cargo registry under $CARGO_HOME; the
# re-run resolves crates from that cache (runtime exports CARGO_NET_OFFLINE=true).
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

cd "$SRC"

# Debug-info contract (SPEC §6.2 item 10): DWARF < 4, threaded through RUSTFLAGS.
# Rust path: sanitizers ride RUSTFLAGS (-Zsanitizer=address below), not $SANITIZER_FLAGS
# (those are C/C++ flags; rustc would reject them). The cc-built libFuzzer runtime gets
# -gdwarf-3 via CFLAGS/CXXFLAGS so the linked binary's first CU stays DWARF < 4.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -Z dwarf-version=3 -C force-frame-pointers=yes}"
export CFLAGS="${CFLAGS:-} -gdwarf-3"
export CXXFLAGS="${CXXFLAGS:-} -gdwarf-3"

# OSS-Fuzz Rust libFuzzer+ASan flags for the fuzz binaries.
FUZZ_RUSTFLAGS="--cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

TRIPLE="x86_64-unknown-linux-gnu"

# Upstream ships two cargo-fuzz crates; build each with its own fuzz dir.
#   fuzz_target_cbor  <- apps/vault/libraries/cbor/fuzz
#   store             <- apps/vault/libraries/persistent_store/fuzz
build_fuzz() { # <fuzz-dir> <target>
  local dir="$1" t="$2"
  echo "--- cargo fuzz build: $t (fuzz dir $dir) ---"
  RUSTFLAGS="$FUZZ_RUSTFLAGS" cargo fuzz build --fuzz-dir "$dir" -O --debug-assertions "$t"
  local bin="$SRC/$dir/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
}

echo "=== cargo fuzz build (image nightly, ASan via RUSTFLAGS) ==="
echo "FUZZ_RUSTFLAGS=$FUZZ_RUSTFLAGS"
# Upstream's cbor fuzz crate no longer compiles (cbor::write API changed under it);
# mayhem/fuzz-cbor is the additive fixed port of the same harness/code path.
build_fuzz mayhem/fuzz-cbor fuzz_target_cbor
# Upstream's persistent_store fuzz crate needs the crate's `std` feature, which is
# broken at tip (driver/model/store still import the removed src/format.rs), and the
# ported Store is a live pddb-service client; mayhem/fuzz-store is the additive
# in-process replacement over the crate's surviving host-side storage path.
build_fuzz mayhem/fuzz-store store

# Pre-build the upstream test suite with the project's NORMAL flags (clean,
# non-sanitized) so mayhem/test.sh never compiles. ctap-crypto's wycheproof
# known-answer suite is the only upstream test that still compiles host-side:
# the workspace targets riscv32imac-unknown-xous-elf hardware/renode (upstream CI
# runs `cargo xtask <board>` builds, never `cargo test`), and the vendored
# cbor/persistent_store/ctap-crypto unit tests are bit-rotted (compile errors at tip).
echo "=== pre-building upstream test suite (ctap-crypto wycheproof) ==="
RUSTFLAGS="$RUST_DEBUG_FLAGS" cargo test --no-run -p ctap-crypto --test wycheproof

echo "build.sh complete"
