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

# 2. Every file the player invokes as a program must be committed executable.
#    A non-executable CGI fails at RUNTIME (busybox httpd just refuses it), and a
#    non-executable early-squeeze.sh re-arms the loud boot buzz.
sh "$root/tools/check-repo-modes.sh" || {
  echo ""
  echo "pre-commit: repo file-mode gate FAILED - commit refused."
  exit 1
}
HOOK
chmod +x "$hook"
echo "installed: $hook"
