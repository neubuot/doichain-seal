#!/usr/bin/env bash
# Doichain Seal: anchors the SHA-256 of release files in the Doichain blockchain.
# Runs inside GitHub Actions. The job proves its identity with a GitHub OIDC token
# (permissions: id-token: write), so no API key or secret is needed.
set -euo pipefail

API="${INPUT_API_URL:-https://doi-api.sendlabs.de}"
API="${API%/}"
AUDIENCE="doichain-seal"
WAIT="${INPUT_WAIT:-0}"
FAIL_ON_ERROR="${INPUT_FAIL_ON_ERROR:-true}"
WRITE_SUMMARY="${INPUT_SUMMARY:-true}"
NOTE="${INPUT_NOTE:-}"
RETRY="${INPUT_RETRY:-2}"
RETRY_WAIT=600

log()  { echo "$*"; }
warn() { echo "::warning::$*"; }
err()  { echo "::error::$*"; }

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { err "Doichain Seal needs '$tool' on the runner"; exit 1; }
done

if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  err "No OIDC token available. Add to the job:  permissions:  id-token: write  (and contents: read)"
  exit 1
fi

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else err "Neither sha256sum nor shasum found"; exit 1; fi
}

size_of() { wc -c < "$1" | tr -d ' '; }

get_token() {
  local response
  response=$(curl -sS --retry 3 --retry-delay 2 -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${AUDIENCE}") || { err "Could not request the OIDC token from GitHub"; exit 1; }
  echo "$response" | jq -r '.value // empty'
}

# Collect files from the glob list (one pattern per line, blank lines ignored, directories skipped).
shopt -s nullglob globstar
FILES=()
while IFS= read -r pattern; do
  pattern="${pattern#"${pattern%%[![:space:]]*}"}"
  pattern="${pattern%"${pattern##*[![:space:]]}"}"
  [ -z "$pattern" ] && continue
  matched=0
  for f in $pattern; do
    if [ -f "$f" ]; then FILES+=("$f"); matched=1; fi
  done
  [ "$matched" = 0 ] && warn "No file matches '$pattern'"
done <<< "${INPUT_FILES:-}"

if [ "${#FILES[@]}" = 0 ]; then
  err "No files to seal. Check the 'files' input (one glob per line, for example dist/*)"
  exit 1
fi

TOKEN=$(get_token)
[ -n "$TOKEN" ] || { err "GitHub returned an empty OIDC token"; exit 1; }
TOKEN_AT=$(date +%s)

RESULTS="[]"
SEALED=0
FAILED=0
REPO_PAGE=""
BADGE=""
BADGE_MD=""

for file in "${FILES[@]}"; do
  name=$(basename -- "$file")
  hash=$(sha256_of "$file")
  size=$(size_of "$file")
  # GitHub OIDC tokens are short-lived, refresh after four minutes for long file lists.
  if [ $(( $(date +%s) - TOKEN_AT )) -gt 240 ]; then TOKEN=$(get_token); TOKEN_AT=$(date +%s); fi
  body=$(jq -cn --arg h "$hash" --arg f "${name:0:80}" --argjson s "$size" --arg n "${NOTE:0:60}" \
    '{hash:$h, filename:$f, size:$s} + (if $n != "" then {note:$n} else {} end)')
  attempt=0
  while :; do
    response=$(curl -sS --retry 2 --retry-delay 3 -w '\n%{http_code}' -X POST "$API/v1/seal/github" \
      -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "User-Agent: doichain-seal-action" \
      --data "$body") || { response=$'\n000'; }
    code="${response##*$'\n'}"
    json="${response%$'\n'*}"
    # 503: the service waits for the next block (chain limit). Retry after Retry-After seconds, at most RETRY times.
    if [ "$code" = "503" ] && [ "$attempt" -lt "$RETRY" ]; then
      attempt=$((attempt + 1))
      log "… service busy (waiting for the next Doichain block), retry $attempt/$RETRY in ${RETRY_WAIT}s"
      sleep "$RETRY_WAIT"
      if [ $(( $(date +%s) - TOKEN_AT )) -gt 240 ]; then TOKEN=$(get_token); TOKEN_AT=$(date +%s); fi
      continue
    fi
    break
  done
  case "$code" in
    201)
      txid=$(echo "$json" | jq -r '.anchoring.txid // empty')
      proof=$(echo "$json" | jq -r '.proof_url')
      log "✔ sealed   $file  sha256=$hash  tx=$txid"
      status="anchored"; SEALED=$((SEALED + 1)) ;;
    200)
      txid=$(echo "$json" | jq -r '.proof.first_anchored.txid // .proof.txid // empty')
      proof=$(echo "$json" | jq -r '.proof_url')
      height=$(echo "$json" | jq -r '.proof.first_anchored.height // .proof.height // "pending"')
      log "✔ already  $file  sha256=$hash  (sealed earlier, block $height)"
      status="already_anchored"; SEALED=$((SEALED + 1)) ;;
    *)
      message=$(echo "$json" | jq -r '.error.message // .detail // empty' 2>/dev/null || true)
      [ -n "$message" ] || message="HTTP $code"
      if [ "$FAIL_ON_ERROR" = "true" ]; then err "Could not seal $file: $message"; else warn "Could not seal $file: $message"; fi
      txid=""; proof="$API/seal/$hash"; status="failed"; FAILED=$((FAILED + 1)) ;;
  esac
  if [ -z "$REPO_PAGE" ] && [ "$status" != "failed" ]; then
    REPO_PAGE=$(echo "$json" | jq -r '.repo_page_url // empty')
    BADGE=$(echo "$json" | jq -r '.repo_badge_url // empty' | sed 's#/badge\.svg$#/seal.svg#')
    BADGE_MD=$(echo "$json" | jq -r '.badge_markdown // empty' | sed 's#/badge\.svg)#/seal.svg)#')
  fi
  RESULTS=$(echo "$RESULTS" | jq -c --arg f "$file" --argjson s "$size" --arg h "$hash" --arg st "$status" --arg t "$txid" --arg p "$proof" --arg b "$API/seal/$hash/badge.svg" \
    '. + [{file:$f, size:$s, hash:$h, status:$st, txid:$t, proof_url:$p, badge_url:$b}]')
done

# Fallback links when nothing could be sealed (repository is known from the runner).
if [ -z "$REPO_PAGE" ]; then
  REPO_PAGE="$API/seal/github/${GITHUB_REPOSITORY:-owner/repo}"
  BADGE="$REPO_PAGE/seal.svg"
  BADGE_MD="[![Doichain Seal]($BADGE)]($REPO_PAGE)"
fi

# Optionally wait for the first confirmation (one block, usually within 10 minutes).
if [ "${WAIT:-0}" -gt 0 ] 2>/dev/null; then
  deadline=$(( $(date +%s) + WAIT ))
  pending=$(echo "$RESULTS" | jq -r '.[] | select(.status == "anchored") | .hash')
  for hash in $pending; do
    while [ "$(date +%s)" -lt "$deadline" ]; do
      st=$(curl -sS "$API/v1/poe/$hash" | jq -r '.status // "unknown"' 2>/dev/null || echo unknown)
      if [ "$st" = "confirmed" ]; then
        height=$(curl -sS "$API/v1/poe/$hash" | jq -r '.first_anchored.height // .height')
        log "✔ confirmed ${hash:0:16}… in block $height"
        RESULTS=$(echo "$RESULTS" | jq -c --arg h "$hash" 'map(if .hash == $h then .status = "confirmed" else . end)')
        break
      fi
      sleep 30
    done
  done
fi

{
  echo "results=$RESULTS"
  echo "sealed=$SEALED"
  echo "failed=$FAILED"
  echo "repo-page-url=$REPO_PAGE"
  echo "badge-url=$BADGE"
  echo "badge-markdown=$BADGE_MD"
} >> "$GITHUB_OUTPUT"

if [ "$WRITE_SUMMARY" = "true" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "## Doichain Seal"
    echo
    echo "[![Doichain Seal]($BADGE)]($REPO_PAGE)"
    echo
    echo "| File | SHA-256 | Status | Proof |"
    echo "|---|---|---|---|"
    echo "$RESULTS" | jq -r '.[] | "| `\(.file)` | `\(.hash[0:16])…` | \(.status) | [open](\(.proof_url)) |"'
    echo
    echo "Add the seal to your README (compact variant: replace seal.svg with badge.svg):"
    echo
    echo '```markdown'
    echo "$BADGE_MD"
    echo '```'
    echo
    echo "The proof is the name \`poe/<sha256>\` on the public Doichain blockchain. Verify a download with \`sha256sum\` and compare it with the proof page."
  } >> "$GITHUB_STEP_SUMMARY"
fi

log "Sealed: $SEALED, failed: $FAILED. Repository page: $REPO_PAGE"
if [ "$FAILED" -gt 0 ] && [ "$FAIL_ON_ERROR" = "true" ]; then exit 1; fi
