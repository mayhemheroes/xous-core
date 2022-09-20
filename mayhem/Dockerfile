# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd apps/vault/libraries/persistent_store/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    bash -c "pushd apps/vault/libraries/cbor/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv apps/vault/libraries/persistent_store/fuzz/target/x86_64-unknown-linux-gnu/release/store /store && \
    mv apps/vault/libraries/cbor/fuzz/target/x86_64-unknown-linux-gnu/release/fuzz_target_cbor /fuzz_target_cbor && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd apps/vault/libraries/persistent_store/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    bash -c "pushd apps/vault/libraries/cbor/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv apps/vault/libraries/persistent_store/fuzz/target/release/store /store_no_inst && \
    mv apps/vault/libraries/cbor/fuzz/target/release/fuzz_target_cbor /fuzz_target_cbor_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /store /store_no_inst /
COPY --from=builder /fuzz_target_cbor /fuzz_target_cbor_no_inst /
