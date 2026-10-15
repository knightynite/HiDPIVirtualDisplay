#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/build/tests/clang-module-cache}"
export SWIFT_MODULECACHE_PATH="${SWIFT_MODULECACHE_PATH:-$PWD/build/tests/swift-module-cache}"

swiftc -parse-as-library \
    -module-cache-path "$SWIFT_MODULECACHE_PATH" \
    Sources/DisplayRecovery.swift Tests/DisplayRecoveryTests.swift \
    -o build/tests/DisplayRecoveryTests
build/tests/DisplayRecoveryTests
