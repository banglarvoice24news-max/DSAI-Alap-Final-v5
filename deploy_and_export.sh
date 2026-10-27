#!/usr/bin/env bash
#
# deploy_and_export.sh — one-shot release driver for the dsaialap mobile app.
#
# It (1) commits the current clean source tree, (2) pushes to GitHub, (3)
# triggers .github/workflows/build-apk.yml (split-per-ABI release build), then
# (4) waits for the run and prints the direct GitHub Release download links.
#
# Usage:
#   VERSION=v1.2.0 ./deploy_and_export.sh
#
# Requirements: git, gh (authenticated), and push access to origin.

set -euo pipefail

VERSION="${VERSION:-v1.0.0}"
API_BASE_URL="${API_BASE_URL:-https://dsaialap.banglarvoice24news.com}"
WORKFLOW_FILE="build-apk.yml"

log() { printf '[%s] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"
command -v gh  >/dev/null 2>&1 || die "gh CLI is required: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"

remote_url="$(git remote get-url origin 2>/dev/null || true)"
[ -n "${remote_url}" ] || die "no git remote 'origin'. Add it first: git remote add origin <url>"

REPO="$(printf '%s\n' "${remote_url}" | sed -E 's#^((git@[^:]+|https?://[^/]+))[:/]##; s#\.git$##')"
[ -n "${REPO}" ] || die "could not derive owner/repo from remote: ${remote_url}"

log "target repository: ${REPO}"
log "release tag:       ${VERSION}"
log "api base url:      ${API_BASE_URL}"

# Never let build output or machine-local caches leak into the release commit.
if git status --porcelain --ignored --untracked-files=all | grep -qE 'mobile/build/|mobile/\.dart_tool/'; then
  log "note: build/ or .dart_tool/ detected — they are ignored and will not be committed"
fi

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -m "build: release ${VERSION}"
  log "committed working tree as 'build: release ${VERSION}'"
else
  log "nothing to commit, working tree is clean"
fi

git push origin HEAD
log "pushed HEAD to origin"

log "triggering ${WORKFLOW_FILE}"
gh workflow run "${WORKFLOW_FILE}" --repo "${REPO}" \
  -f release_tag="${VERSION}" \
  -f api_base_url="${API_BASE_URL}"

run_id=""
for _ in $(seq 1 30); do
  run_id="$(gh run list --repo "${REPO}" --workflow="${WORKFLOW_FILE}" --limit 5 \
    --json databaseId,event --jq '[.[] | select(.event=="workflow_dispatch")][0].databaseId // empty')"
  [ -n "${run_id}" ] && break
  sleep 2
done
[ -n "${run_id}" ] || die "could not find the triggered workflow run"

log "watching run ${run_id}"
watch_status=0
gh run watch "${run_id}" --repo "${REPO}" --exit-status --interval 10 || watch_status=$?

echo
echo "================================================================"
echo " GitHub Release APK download links (${VERSION})"
echo "================================================================"
gh api "repos/${REPO}/releases/tags/${VERSION}" \
  --jq '.assets[] | .name + ": " + .browser_download_url' 2>/dev/null \
  || log "release not found (build may have failed) — check the run above"
echo "Release page: https://github.com/${REPO}/releases/tag/${VERSION}"
echo "================================================================"

exit "${watch_status}"
