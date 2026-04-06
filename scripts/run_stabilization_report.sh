#!/usr/bin/env bash

set -u -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS_DIR="$ROOT_DIR/docs/reports"
FILE_TS="$(date '+%Y%m%d-%H%M%S')"
RUN_TS="$(date '+%Y-%m-%d %H:%M:%S %z')"
LOG_DIR="$REPORTS_DIR/logs/$FILE_TS"
REPORT_PATH="$REPORTS_DIR/stabilization-$FILE_TS.md"
LATEST_PATH="$REPORTS_DIR/latest.md"

mkdir -p "$LOG_DIR"

HOST_NAME="$(scutil --get ComputerName 2>/dev/null || hostname)"
OS_VERSION="$(sw_vers -productVersion 2>/dev/null || uname -r)"
ARCH="$(uname -m)"
SWIFT_VERSION="$(swift --version 2>/dev/null | head -n 1 || echo "unknown")"

declare -a CHECK_NAMES=()
declare -a CHECK_STATUSES=()
declare -a CHECK_DURATIONS=()
declare -a CHECK_LOGS=()
declare -a CHECK_COMMANDS=()

run_check() {
    local name="$1"
    shift
    local safe_name
    safe_name="$(echo "$name" | sed -E 's/[^A-Za-z0-9._-]+/_/g')"
    local log_path="$LOG_DIR/${safe_name}.log"
    local started=$SECONDS
    local command_pretty
    command_pretty="$(printf "%q " "$@")"
    command_pretty="${command_pretty% }"

    CHECK_NAMES+=("$name")
    CHECK_COMMANDS+=("$command_pretty")
    CHECK_LOGS+=("${log_path#$ROOT_DIR/}")

    "$@" >"$log_path" 2>&1
    local status=$?

    local elapsed=$((SECONDS - started))
    if [[ $status -eq 0 ]]; then
        CHECK_STATUSES+=("PASS")
    else
        CHECK_STATUSES+=("BLOCK")
    fi
    CHECK_DURATIONS+=("${elapsed}s")
}

run_check "Build" swift build --package-path "$ROOT_DIR"
run_check "All tests" swift test --package-path "$ROOT_DIR"
run_check "Word import/export tests" swift test --package-path "$ROOT_DIR" --filter WordDocumentServiceTests
run_check "Performance smoke tests" swift test --package-path "$ROOT_DIR" --filter EditorPerformanceTests
run_check "Project settings compatibility tests" swift test --package-path "$ROOT_DIR" --filter ProjectServiceTests

VERDICT="PASS"
for status in "${CHECK_STATUSES[@]}"; do
    if [[ "$status" != "PASS" ]]; then
        VERDICT="BLOCK"
        break
    fi
done

{
    echo "# Stabilization Report"
    echo
    echo "Date: $RUN_TS"
    echo "Host: $HOST_NAME"
    echo "OS: macOS $OS_VERSION ($ARCH)"
    echo "Swift: $SWIFT_VERSION"
    echo
    echo "Release verdict: $VERDICT"
    echo
    echo "## Checks"
    echo "| Check | Status | Duration | Command | Log |"
    echo "|---|---|---:|---|---|"

    local_count="${#CHECK_NAMES[@]}"
    for ((i = 0; i < local_count; i++)); do
        echo "| ${CHECK_NAMES[$i]} | ${CHECK_STATUSES[$i]} | ${CHECK_DURATIONS[$i]} | \`${CHECK_COMMANDS[$i]}\` | \`${CHECK_LOGS[$i]}\` |"
    done

    echo
    echo "## Notes"
    if [[ "$VERDICT" == "PASS" ]]; then
        echo "- All automated checks passed."
    else
        echo "- At least one check failed. See logs for details."
    fi
    echo "- Manual UI checks are still required (interactive workflow in app)."
} >"$REPORT_PATH"

cp "$REPORT_PATH" "$LATEST_PATH"

echo "Report: $REPORT_PATH"
echo "Latest: $LATEST_PATH"
echo "Verdict: $VERDICT"

if [[ "$VERDICT" != "PASS" ]]; then
    exit 1
fi
