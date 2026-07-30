#!/bin/sh
# Install the repo's git hooks. Run once after cloning:  sh tools/install-hooks.sh
# (.git/hooks is not version-controlled, so the hook itself has to be installed.)
set -e
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook="$root/.git/hooks/pre-commit"
mkdir -p "$root/.git/hooks"
cat > "$hook" <<'HOOK'
#!/bin/sh
# Two gates, both fail-closed.
root="$(git rev-parse --show-toplevel)"

# 1. No personal / environment-specific data in this PUBLIC repo.
NODE="$(command -v node || echo /c/Users/nzilb/tools/node-dist/node.exe)"
"$NODE" "$root/tools/scan-personal-data.mjs" --staged || {
  echo ""
  echo "pre-commit: personal-data scan FAILED - commit refused."
  echo "Run: node tools/scan-personal-data.mjs --staged"
  exit 1
}

# 2. The page must PARSE. One inline script block means one SyntaxError ships a
#    completely dead app (happened: a sed-eaten backslash in a regex, build b213).
"$NODE" "$root/tools/check-page-parses.mjs" || {
  echo ""
  echo "pre-commit: page-parse gate FAILED - commit refused."
  exit 1
}

# 3. Every file the player invokes as a program must be committed executable.
sh "$root/tools/check-repo-modes.sh" || {
  echo ""
  echo "pre-commit: repo file-mode gate FAILED - commit refused."
  exit 1
}
HOOK
chmod +x "$hook"
chmod +x "$hook"

# commit-msg: a change to a reference-shared subsystem must cite what the reference does.
msghook="$root/.git/hooks/commit-msg"
cat > "$msghook" <<'MSGHOOK'
#!/bin/sh
root="$(git rev-parse --show-toplevel)"
NODE="$(command -v node || echo /c/Users/nzilb/tools/node-dist/node.exe)"
"$NODE" "$root/tools/check-commit-reference.mjs" "$1" || exit 1
MSGHOOK
chmod +x "$msghook"
echo "installed: $msghook"
echo "installed: $hook"
