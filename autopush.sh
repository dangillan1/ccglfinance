#!/bin/bash
# CCGL Dashboard Auto-Push — self-locating, self-healing.
# Runs every 2 min via LaunchAgent. Log: /tmp/ccgl_autopush.log
#
# Accuracy rule: timestamps on the dashboard reflect REAL data refreshes only.
# No synthetic heartbeats. If the nightly update didn't run, "Last refreshed"
# stays at its last true value — that is the correct behavior.

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Resolve our own directory — this is the repo root. No hardcoded paths.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LOG="/tmp/ccgl_autopush.log"

stamp() { date '+%Y-%m-%d %H:%M:%S'; }
log()   { echo "[$(stamp)] $*" >> "$LOG"; }

log "── check started (repo=$SCRIPT_DIR)"
cd "$SCRIPT_DIR" || { log "ERROR: cd failed to $SCRIPT_DIR"; exit 1; }

# Clear any stale locks (main + worktree)
find .git -maxdepth 4 -name '*.lock' -delete 2>/dev/null
rm -f .git/index.new 2>/dev/null

# Stage target files
/usr/bin/git add CCGL_Finance_Dashboard.html index.html 2>/dev/null >> "$LOG" 2>&1

# Commit if anything staged
if /usr/bin/git diff --cached --quiet; then
  log "nothing to commit"
else
  MSG="auto: dashboard updated $(date '+%b %-d %Y · %-I:%M %p')"
  /usr/bin/git commit -m "$MSG" >> "$LOG" 2>&1
  log "✓ committed: $MSG"
fi

# Fetch
/usr/bin/git fetch origin >> "$LOG" 2>&1

# Move aside any untracked files that would collide with incoming tracked files
BACKUP_DIR="/tmp/ccgl_autopush_backup"
mkdir -p "$BACKUP_DIR"
/usr/bin/git ls-tree -r origin/main --name-only 2>/dev/null | while IFS= read -r f; do
  if [ -e "$f" ] && ! /usr/bin/git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    mv -- "$f" "$BACKUP_DIR/$f" 2>/dev/null \
      && log "moved untracked collision: $f"
  fi
done

# Heal divergence: rebase first, fall back to merge -X ours
BEHIND=$(/usr/bin/git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
if [ "${BEHIND:-0}" -gt 0 ]; then
  if /usr/bin/git rebase origin/main >> "$LOG" 2>&1; then
    log "✓ rebased onto origin ($BEHIND behind)"
  else
    log "rebase conflicts — aborting and trying merge -X ours"
    /usr/bin/git rebase --abort >> "$LOG" 2>&1
    if /usr/bin/git merge --no-edit -X ours origin/main >> "$LOG" 2>&1; then
      log "✓ merged origin with -X ours (local wins)"
    else
      log "ERROR: merge -X ours also failed, aborting"
      /usr/bin/git merge --abort >> "$LOG" 2>&1
    fi
  fi
fi

# Push if ahead
AHEAD=$(/usr/bin/git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "${AHEAD:-0}" -gt 0 ]; then
  /usr/bin/git push >> "$LOG" 2>&1 \
    && log "✓ pushed $AHEAD commit(s)" \
    || log "ERROR: push failed"
else
  log "up to date with origin"
fi
