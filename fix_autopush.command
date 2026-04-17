#!/bin/bash
# CCGL Dashboard — autopush rescue tool (v2)
# Double-click this when the dashboard hasn't updated in GitHub for a while.
#
# What it does:
#   1. Removes any stuck git locks
#   2. Aborts any in-progress rebase/merge
#   3. Moves aside ANY untracked local files that collide with tracked files on origin
#      (so origin's tracked versions can come in cleanly). Backups go to /tmp.
#   4. Merges origin/main into local, preferring OUR changes on conflict (-X ours)
#   5. Pushes the healed history to GitHub
#
# Safe to run any time. No-ops when healthy.

set -u
REPO="/Users/dangillan/Documents/Claude/Projects/CCGL Finance"
BACKUP_DIR="/tmp/ccgl_rescue_$(date +%Y%m%d_%H%M%S)"
cd "$REPO" || { echo "ERROR: cannot cd to $REPO"; read -n 1 -r; exit 1; }

echo "── CCGL autopush rescue v2 ──"
echo "Repo:   $REPO"
echo "Backup: $BACKUP_DIR (untracked files that would block the merge)"
echo ""

# 1. Clear stale locks
echo "[1/6] Clearing any stale .git locks..."
find .git -maxdepth 2 -name '*.lock' -delete 2>/dev/null
rm -f .git/index.new 2>/dev/null

# 2. Abort any in-progress rebase/merge
if [ -d .git/rebase-apply ] || [ -d .git/rebase-merge ]; then
  echo "[2/6] Aborting in-progress rebase..."
  git rebase --abort 2>/dev/null || true
else
  echo "[2/6] No rebase in progress ✓"
fi
if [ -f .git/MERGE_HEAD ]; then
  echo "       Aborting in-progress merge..."
  git merge --abort 2>/dev/null || true
fi

# 3. Fetch latest
echo "[3/6] Fetching origin..."
git fetch origin 2>&1 | sed 's/^/       /'

# 4. Move aside untracked files that would collide with origin's tracked files
echo "[4/6] Checking for untracked files that would block the merge..."
mkdir -p "$BACKUP_DIR"
MOVED=0
while IFS= read -r f; do
  # If the path exists locally AND is NOT tracked by us, move it aside.
  if [ -e "$f" ] && ! git ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    mv -- "$f" "$BACKUP_DIR/$f" 2>/dev/null && {
      echo "       moved: $f  →  $BACKUP_DIR/$f"
      MOVED=$((MOVED+1))
    }
  fi
done < <(git ls-tree -r origin/main --name-only)
if [ "$MOVED" -eq 0 ]; then
  echo "       no collisions ✓"
else
  echo "       moved $MOVED colliding file(s) to backup"
fi

# 5. Heal divergence
AHEAD=$(git rev-list --count 'origin/main..HEAD' 2>/dev/null || echo 0)
BEHIND=$(git rev-list --count 'HEAD..origin/main' 2>/dev/null || echo 0)
echo "[5/6] Before heal: local is $AHEAD ahead / $BEHIND behind origin"

if [ "$BEHIND" -gt 0 ] && [ "$AHEAD" -gt 0 ]; then
  echo "       Diverged — merging origin/main with -X ours (local changes win on conflict)..."
  if git merge --no-edit -X ours origin/main 2>&1 | sed 's/^/       /'; then
    echo "       ✓ merge succeeded"
  else
    echo "       merge failed — check above"
  fi
elif [ "$BEHIND" -gt 0 ]; then
  echo "       Only behind — fast-forward merge..."
  git merge --ff-only origin/main 2>&1 | sed 's/^/       /'
else
  echo "       No divergence to heal ✓"
fi

# 6. Push if ahead
AHEAD=$(git rev-list --count 'origin/main..HEAD' 2>/dev/null || echo 0)
if [ "$AHEAD" -gt 0 ]; then
  echo "[6/6] Pushing $AHEAD commit(s) to GitHub..."
  git push 2>&1 | sed 's/^/       /'
else
  echo "[6/6] Nothing to push ✓"
fi

echo ""
echo "── Final status ──"
git status -sb | head -5
echo "..."
echo ""
git log --oneline -5
echo ""
if [ "$MOVED" -gt 0 ]; then
  echo "ℹ  Backed-up untracked files are in: $BACKUP_DIR"
  echo "   (Safe to leave there. Delete anytime with: rm -rf '$BACKUP_DIR')"
  echo ""
fi
echo "Done. Live URL: https://dangillan1.github.io/ccglfinance/"
echo "(Press any key to close)"
read -n 1 -r
