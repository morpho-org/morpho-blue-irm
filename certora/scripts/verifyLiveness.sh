#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    src/Irm.sol \
    --verify Irm:certora/specs/Liveness.spec \
    --msg "IRM Liveness" \
    --solc_via_ir \
    --solc_optimize 200 \
    "$@"
