#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
mkdir -p build/test
result="$PWD/build/test/FTCTeamHub.xcresult"
device="$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
iphones = [d for runtime in sorted(devices, reverse=True) for d in devices[runtime]
           if runtime.split(".")[-1].startswith("iOS-") and d["name"].startswith("iPhone")]
if not iphones:
    sys.exit("No iPhone simulator runtime available")
print(iphones[0]["udid"])
')"
if [[ -e "$result" ]]; then
  result="$PWD/build/test/FTCTeamHub-$(date +%s).xcresult"
fi

status=0
xcodebuild -project FTCTeamHub.xcodeproj -scheme FTCTeamHub \
  -destination "platform=iOS Simulator,id=$device" -resultBundlePath "$result" \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 75 CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | tee build/test/xcodebuild-test.log || status=$?

xcrun xcresulttool export attachments --path "$result" --output-path build/test/screenshots || true
exit "$status"
