#!/bin/sh
# Install the repo's git hooks. Run once after cloning:  sh tools/install-hooks.sh
# (.git/hooks is not version-controlled, so the hook itself has to be installed.)
set -e
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
hook="$root/.git/hooks/pre-commit"
mkdir -p "$root/.git/hooks"
cat > "$hook" <<'HOOK'
#!/bin/sh
# Block personal / environment-specific data from entering this PUBLIC repo.
NODE="$(command -v node || echo /c/Users/nzilb/tools/node-dist/node.exe)"
root="$(git rev-parse --show-toplevel)"
"$NODE" "$root/tools/scan-personal-data.mjs" --staged || {
  echo ""
  echo "pre-commit: personal-data scan FAILED - commit refused."
  echo "Run: node tools/scan-personal-data.mjs --staged"
  exit 1
}
HOOK
chmod +x "$hook"
echo "installed: $hook"
