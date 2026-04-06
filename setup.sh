#!/bin/bash
# CCGL Finance Dashboard — One-Time Setup
# Run this once from Terminal. After this, everything runs nightly at midnight automatically.
# Usage: drag this file into Terminal and press Return

set -e

# ── PATHS (auto-detected) ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON=$(which python3)
PLIST_NAME="com.ccgl.dashboard.nightly"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME.plist"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   CCGL Finance Dashboard — Automated Setup       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "📁 Dashboard folder : $SCRIPT_DIR"
echo "🐍 Python           : $PYTHON"
echo ""

# ── STEP 1: GIT INIT ──────────────────────────────────────────────────────
echo "▶ Step 1/5 — Initializing git repo..."

if [ ! -d "$SCRIPT_DIR/.git" ]; then
    git -C "$SCRIPT_DIR" init -b main
    echo "  ✓ git init"
else
    echo "  ✓ already a git repo"
fi

git -C "$SCRIPT_DIR" config user.name  "CCGL Nightly Bot"
git -C "$SCRIPT_DIR" config user.email "dan@ccgl.bot"

# Prompt for GitHub PAT (only needed once — stored in remote URL)
if [ -z "$GITHUB_TOKEN" ]; then
    echo "  Enter your GitHub Personal Access Token (contents not shown):"
    read -rs GITHUB_TOKEN
    echo ""
fi

REMOTE_URL="https://${GITHUB_TOKEN}@github.com/dangillan1/ccglfinance.git"

# Set remote (update if already exists)
if git -C "$SCRIPT_DIR" remote get-url origin &>/dev/null; then
    git -C "$SCRIPT_DIR" remote set-url origin "$REMOTE_URL"
    echo "  ✓ remote updated (HTTPS + token)"
else
    git -C "$SCRIPT_DIR" remote add origin "$REMOTE_URL"
    echo "  ✓ remote added (HTTPS + token)"
fi

# ── STEP 2: .GITIGNORE ────────────────────────────────────────────────────
echo ""
echo "▶ Step 2/5 — Creating .gitignore..."

cat > "$SCRIPT_DIR/.gitignore" << 'EOF'
update.log
*.pyc
__pycache__/
.DS_Store
*.swp
EOF
echo "  ✓ .gitignore created"

# ── STEP 3: INITIAL COMMIT + PUSH ────────────────────────────────────────
echo ""
echo "▶ Step 3/5 — Initial commit and push..."

cd "$SCRIPT_DIR"
git add CCGL_Finance_Dashboard.html nightly_update.py setup.sh .gitignore
git commit -m "initial dashboard — $(date '+%Y-%m-%d')" || echo "  (nothing new to commit)"
git push -u origin main
echo "  ✓ pushed to GitHub"

# ── STEP 4: LAUNCHD PLIST ─────────────────────────────────────────────────
echo ""
echo "▶ Step 4/5 — Installing launchd scheduler (midnight nightly)..."

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_NAME}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${PYTHON}</string>
    <string>${SCRIPT_DIR}/nightly_update.py</string>
  </array>

  <key>WorkingDirectory</key>
  <string>${SCRIPT_DIR}</string>

  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>0</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>

  <key>StandardOutPath</key>
  <string>${SCRIPT_DIR}/update.log</string>

  <key>StandardErrorPath</key>
  <string>${SCRIPT_DIR}/update.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    <key>HOME</key>
    <string>${HOME}</string>
  </dict>
</dict>
</plist>
EOF

echo "  ✓ plist written → $PLIST_PATH"

# Unload first if already loaded (handles re-runs)
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load -w "$PLIST_PATH"
echo "  ✓ launchd job loaded"

# ── STEP 5: TEST RUN ──────────────────────────────────────────────────────
echo ""
echo "▶ Step 5/5 — Running a test update now to verify everything works..."
echo "  (this will fetch QBO data and push to GitHub — ~10 seconds)"
echo ""

$PYTHON "$SCRIPT_DIR/nightly_update.py"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅  Setup complete!                             ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║                                                  ║"
echo "║  Dashboard URL:                                  ║"
echo "║  https://dangillan1.github.io/ccglfinance/       ║"
echo "║                                                  ║"
echo "║  Updates: nightly at midnight automatically      ║"
echo "║  Logs:    $SCRIPT_DIR/update.log                 ║"
echo "║                                                  ║"
echo "║  Bank balance: drop a screenshot in Cowork       ║"
echo "║  to push a manual update anytime.                ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
