#!/usr/bin/env bash
# Report one workflow run to LumaTrack. Called by action.yml with inputs
# mapped to LT_* env vars; runnable standalone for local testing.
#
# The external id makes reporting idempotent: retries of this script (or
# curl's own retries) land on the same run instead of double-counting.
set -u

fail() {
  if [ "${LT_FAIL_ON_ERROR:-false}" = "true" ]; then
    echo "::error::$1"
    exit 1
  fi
  echo "::warning::$1 (fail-on-error is false; not failing the job)"
  exit 0
}

[ -n "${LT_API_KEY:-}" ] || fail "api-key is required"
[ -n "${LT_AUTOMATION:-}" ] || fail "automation is required"

# The hosted service is where nearly every workflow reports, so an empty
# base-url means that. Composite-action inputs also arrive as empty strings
# rather than unset, so the default in action.yml is not enough on its own.
BASE="${LT_BASE_URL:-https://lumatrack.io}"
BASE="${BASE%/}"

# Default idempotency key: one run per workflow attempt. Set here rather
# than in action.yml, whose input defaults cannot use expressions.
if [ -z "${LT_EXTERNAL_ID:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
  LT_EXTERNAL_ID="${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
fi

# Every GitHub job status now maps to a status of its own, so nothing is
# reported as something it was not. A `skipped` job was gated out: no work, no
# breakage. A `cancelled` job was interrupted part way. Neither earns value and
# neither counts as a failure; whether they carry the automation's per-run cost
# is set per automation in LumaTrack (cancellations are charged by default,
# skips are not). The reason is preserved so the Pareto can tell them apart.
STATUS="${LT_STATUS:-success}"
REASON="${LT_FAILURE_REASON:-}"
case "$STATUS" in
  success) ;;
  failure) ;;
  skipped) [ -n "$REASON" ] || REASON="ci/skipped" ;;
  cancelled) [ -n "$REASON" ] || REASON="ci/cancelled" ;;
  *) fail "status must be success, failure, cancelled, or skipped (got '$STATUS')" ;;
esac

if [ -n "${LT_METADATA:-}" ]; then
  if ! echo "$LT_METADATA" | jq -e 'type == "object"' >/dev/null 2>&1; then
    fail "metadata must be a JSON object"
  fi
fi

BODY=$(jq -n \
  --arg automation "$LT_AUTOMATION" \
  --arg status "$STATUS" \
  --arg external_id "${LT_EXTERNAL_ID:-}" \
  --arg reason "$REASON" \
  --arg duration "${LT_DURATION_SECONDS:-}" \
  --arg units "${LT_UNITS:-}" \
  --argjson metadata "${LT_METADATA:-null}" \
  '{automation: $automation, status: $status, source: "github-actions"}
   + (if $external_id != "" then {external_id: $external_id} else {} end)
   + (if $reason != "" then {failure_reason: $reason} else {} end)
   + (if $duration != "" then {duration_seconds: ($duration | tonumber)} else {} end)
   + (if $units != "" then {units: ($units | tonumber)} else {} end)
   + (if $metadata != null then {metadata: $metadata} else {} end)') \
  || fail "could not build the request body (are duration-seconds and units numeric?)"

RESPONSE=$(curl -sS --max-time 15 --retry 2 --retry-delay 2 \
  -w '\n%{http_code}' \
  -X POST "$BASE/api/v1/runs" \
  -H "Authorization: Bearer $LT_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>&1) || fail "could not reach LumaTrack: $RESPONSE"

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
PAYLOAD=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  2*) ;;
  *) fail "LumaTrack answered HTTP $HTTP_CODE: $(echo "$PAYLOAD" | head -c 300)" ;;
esac

RUN_ID=$(echo "$PAYLOAD" | jq -r '.run.id // empty' 2>/dev/null)
DEDUP=$(echo "$PAYLOAD" | jq -r '.deduplicated // false' 2>/dev/null)
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "run-id=$RUN_ID" >> "$GITHUB_OUTPUT"
  echo "deduplicated=$DEDUP" >> "$GITHUB_OUTPUT"
fi
echo "Reported $STATUS run to LumaTrack (run $RUN_ID, deduplicated=$DEDUP)."
