#!/bin/bash
# One-shot unstick: clears stale sandbox-owned locks, pushes any pending commits,
# then re-runs the autopush LaunchAgent to confirm it's healthy.
set -e
cd "$(dirname "$0")"
echo "── Removing stale locks ──"
sudo rm -f .git/index.lock .git/index.lock.stale .git/HEAD.lock .git/refs/heads/main.lock || true
echo "── Status ──"
git status -sb
echo "── Pushing any ahead-of-origin commits ──"
git push
echo "── Triggering autopush LaunchAgent ──"
launchctl kickstart -k "gui/$(id -u)/com.ccgl.dashboard.autopush" 2>/dev/null || true
echo "── Last 10 log lines ──"
tail -10 /tmp/ccgl_autopush.log 2>/dev/null || echo "(no log yet)"
echo ""
echo "✓ Done. Live site should update within ~30s."
echo "Press any key to close…"
read -n 1
