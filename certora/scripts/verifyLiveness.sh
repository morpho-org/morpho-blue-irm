#!/bin/bash

set -euxo pipefail

certoraRun \
    src/Irm.sol \
    --verify Irm:certora/specs/Liveness.spec \
    --msg "IRM Liveness" \
    --solc_via_ir \
    --solc_optimize 200 \
    "$@"
