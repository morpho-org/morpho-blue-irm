#!/bin/bash

set -euxo pipefail

certoraRun \
    certora/harness/LibHarness.sol \
    --verify LibHarness:certora/specs/Unchecked.spec \
    --msg "IRM Unchecked" \
    --solc_via_ir \
    --solc_optimize 200 \
    "$@"
