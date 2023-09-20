#!/bin/bash

set -euxo pipefail

make -C certora munged

certoraRun \
    certora/munged/Irm.sol \
    --verify Irm:certora/specs/Liveness.spec \
    --msg "IRM Liveness" \
    --solc_via_ir \
    --solc_optimize 200 \
    "$@"
