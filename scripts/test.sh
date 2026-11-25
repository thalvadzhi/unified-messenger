#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -target arm64-apple-macosx14.0 Sources/Core/*.swift Tests/*.swift -o build/run-tests
build/run-tests
