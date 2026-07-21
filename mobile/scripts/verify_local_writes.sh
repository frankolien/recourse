#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RPC_PORT="${MOBILE_ANVIL_PORT:-8547}"
RPC_URL="http://127.0.0.1:${RPC_PORT}"
DEPLOYMENT="${ROOT}/deployments/local-31337.json"
SEED="${ROOT}/deployments/seed-local-31337.json"
ANVIL_LOG="${TMPDIR:-/tmp}/recourse-mobile-anvil.log"
DEPLOYER_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
BUYER_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
SIMULATOR_NAME="${MOBILE_SIMULATOR:-iPhone 16 Pro}"
SIMULATOR_ID="$({ xcrun simctl list devices available -j | jq -r --arg name "${SIMULATOR_NAME}" '
  [.devices[][] | select(.name == $name and .isAvailable == true)][0].udid // empty
'; } 2>/dev/null)"

if [[ -z "${SIMULATOR_ID}" ]]; then
  echo "No available simulator named ${SIMULATOR_NAME}" >&2
  exit 1
fi

cleanup() {
  kill "${ANVIL_PID:-}" 2>/dev/null || true
  (
    cd "${ROOT}/mobile"
    env -u MOBILE_LOCAL_WRITE_TESTS \
      -u MOBILE_LOCAL_RPC_URL \
      -u MOBILE_LOCAL_DEPLOYMENT \
      -u MOBILE_LOCAL_SEED \
      -u MOBILE_LOCAL_BUYER_PK \
      ruby scripts/generate_project.rb >/dev/null
  )
}

anvil --silent --port "${RPC_PORT}" >"${ANVIL_LOG}" 2>&1 &
ANVIL_PID=$!
trap cleanup EXIT

for _ in $(seq 1 40); do
  if cast block-number --rpc-url "${RPC_URL}" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
cast block-number --rpc-url "${RPC_URL}" >/dev/null

(
  cd "${ROOT}/contracts"
  RECOURSE_RESOLVE_DELAY=0 forge script script/Deploy.s.sol:Deploy \
    --rpc-url "${RPC_URL}" \
    --private-key "${DEPLOYER_PK}" \
    --broadcast
)

ARC_RPC_URL="${RPC_URL}" DEPLOYER_PK="${DEPLOYER_PK}" \
  node "${ROOT}/engine/scripts/seed.mjs" "${DEPLOYMENT}"

export MOBILE_LOCAL_WRITE_TESTS=1
export MOBILE_LOCAL_RPC_URL="${RPC_URL}"
export MOBILE_LOCAL_DEPLOYMENT="${DEPLOYMENT}"
export MOBILE_LOCAL_SEED="${SEED}"
export MOBILE_LOCAL_BUYER_PK="${BUYER_PK}"

(
  cd "${ROOT}/mobile"
  ruby scripts/generate_project.rb
)

xcodebuild -quiet \
  -project "${ROOT}/mobile/Recourse.xcodeproj" \
  -scheme Recourse \
  -destination "platform=iOS Simulator,id=${SIMULATOR_ID}" \
  -derivedDataPath "${TMPDIR:-/tmp}/recourse-ios-local-writes" \
  -clonedSourcePackagesDirPath "${TMPDIR:-/tmp}/recourse-spm-write" \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  -only-testing:RecourseTests/ArcLocalWriteTests test
