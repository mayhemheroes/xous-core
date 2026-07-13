#!/usr/bin/env bash
#
# mayhem/test.sh — RUN xous-core's upstream host-runnable test suite: ctap-crypto's
# wycheproof known-answer vectors (pre-built by mayhem/build.sh with the same flags,
# so this only re-runs the cached binary). It asserts crypto outputs against Google's
# Wycheproof test vectors — behavioral, not an exit-code oracle.
#
# Everything else upstream ships is skipped because it cannot run: the workspace
# targets riscv32imac-unknown-xous-elf hardware/renode (upstream CI runs
# `cargo xtask <board>` builds, never `cargo test`), and the vendored
# cbor/persistent_store/ctap-crypto/ux-api/flatipc unit tests fail to compile at tip.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"
cd "$SRC"

: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -Z dwarf-version=3 -C force-frame-pointers=yes}"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

LOG=/tmp/xous-core-tests.log
RUSTFLAGS="$RUST_DEBUG_FLAGS" cargo test -p ctap-crypto --test wycheproof \
  -- --test-threads="$MAYHEM_JOBS" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}

passed=0; failed=0; skipped=0
while read -r p f s; do
  passed=$((passed + p)); failed=$((failed + f)); skipped=$((skipped + s))
done < <(sed -n 's/^test result: [a-zA-Z]*\.* \([0-9]*\) passed; \([0-9]*\) failed; \([0-9]*\) ignored.*/\1 \2 \3/p' "$LOG")

if [ "$passed" -eq 0 ] && [ "$failed" -eq 0 ]; then
  echo "test.sh: no test results parsed — cargo test did not run (build.sh must pre-build the suites)" >&2
  emit_ctrf cargo-test 0 1; exit 1
fi
[ "$rc" -ne 0 ] && [ "$failed" -eq 0 ] && failed=1

emit_ctrf cargo-test "$passed" "$failed" "$skipped"
