#!/bin/bash
cd /Users/dangillan/ccgl_dashboard

echo "── CCGL Force Push ──"
echo ""

# Clean up any stuck rebase/merge state
git rebase --abort 2>/dev/null && echo "▶ Cleared stuck rebase" || true
git merge --abort 2>/dev/null || true
rm -f .git/index.lock .git/HEAD.lock .git/MERGE_HEAD .git/rebase-merge/head-name 2>/dev/null

# Force push our version
echo "▶ Force pushing..."
GIT_TERMINAL_PROMPT=0 git push --force origin main 2>&1 \
  && echo "" && echo "✓ Done! Refresh site in ~30 seconds." \
  || echo "" && echo "✗ Failed — paste output to Claude."

echo ""
read -p "Press Enter to close..."
