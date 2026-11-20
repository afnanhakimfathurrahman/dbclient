#!/usr/bin/env bash
# Waits for the GitHub Actions CI run of the current commit and prints why it
# failed: the failing step, analyzer issues and failing tests.
# Needs GITHUB_TOKEN. Usage: ci-check.sh [commit-sha]
set -euo pipefail

: "${GITHUB_TOKEN:?Set GITHUB_TOKEN (repo/actions read access) first}"
sha="${1:-$(git rev-parse HEAD)}"
remote="$(git remote get-url origin)"
repo="$(sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' <<<"$remote")"
api="https://api.github.com/repos/$repo"
tmp="${TMPDIR:-/tmp}"

gh_api() {
  curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" "$@"
}

echo "Waiting for CI on $repo @ ${sha:0:7}…"
run=""
for _ in $(seq 1 90); do # up to ~30 minutes
  run="$(gh_api "$api/actions/runs?head_sha=$sha&per_page=20" | python3 -c '
import json, sys
runs = [r for r in json.load(sys.stdin)["workflow_runs"] if r["name"] == "CI"]
if runs:
    r = runs[0]
    print(r["id"], r["status"], r["conclusion"] or "-")
')"
  if [[ -n "$run" && "$(cut -d' ' -f2 <<<"$run")" == completed ]]; then break; fi
  sleep 20
done

[[ -n "$run" ]] || { echo "No CI run found for ${sha:0:7} (pushed?)"; exit 2; }
read -r id status conclusion <<<"$run"
echo "CI run $id: $status / $conclusion"
[[ "$status" == completed ]] || { echo "Still running; check again later."; exit 3; }
[[ "$conclusion" == success ]] && exit 0

gh_api "$api/actions/runs/$id/jobs" | python3 -c '
import json, sys
for job in json.load(sys.stdin)["jobs"]:
    for step in job["steps"]:
        if step["conclusion"] == "failure":
            print(job["id"], step["name"])
' | while read -r job step; do
  echo "Failed step: $step"
  gh_api "$api/actions/jobs/$job/logs" -o "$tmp/ci-$job.log"
  # Strip timestamps; show analyzer issues, test failures and errors.
  sed -E 's/^[0-9T:.-]+Z //' "$tmp/ci-$job.log" |
    grep -E ' (error|warning|info) • |issues? found|\[E\]|Some tests failed|^Error|Exception' |
    head -60 || true
  echo "Full log: $tmp/ci-$job.log"
done
exit 1
