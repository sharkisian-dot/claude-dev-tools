#!/usr/bin/env bash
# install.sh — Install claude-dev-tools into a project repo
#
# Usage (from the project repo root):
#   bash path/to/claude-dev-tools/install.sh
#
# What it does:
#   1. Creates .devtools.yaml from the example template (if not exists)
#   2. Creates .devtools/agents/ directory for project overrides
#   3. Adds devtools to PATH suggestion
#   4. Makes all bin/ scripts executable

set -euo pipefail

DEVTOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(pwd)"

echo "Installing claude-dev-tools into: $REPO_ROOT"
echo "  Tooling location: $DEVTOOLS_ROOT"
echo ""

# 1. Create config file
if [[ ! -f "${REPO_ROOT}/.devtools.yaml" ]]; then
  cp "${DEVTOOLS_ROOT}/.devtools.yaml.example" "${REPO_ROOT}/.devtools.yaml"
  echo "✓ Created .devtools.yaml (edit this with your project settings)"
else
  echo "⏭  .devtools.yaml already exists — skipping"
fi

# 2. Create agent overrides directory
mkdir -p "${REPO_ROOT}/.devtools/agents"
echo "✓ Created .devtools/agents/ (drop override .md files here)"

# 3. Make scripts executable
chmod +x "${DEVTOOLS_ROOT}"/bin/* 2>/dev/null || true
echo "✓ Made bin/ scripts executable"

# 4. Add to .gitignore if needed
if [[ -f "${REPO_ROOT}/.gitignore" ]]; then
  if ! grep -q '.relay-locks' "${REPO_ROOT}/.gitignore" 2>/dev/null; then
    echo "" >> "${REPO_ROOT}/.gitignore"
    echo "# devtools" >> "${REPO_ROOT}/.gitignore"
    echo ".relay-locks/" >> "${REPO_ROOT}/.gitignore"
    echo ".screenshots/" >> "${REPO_ROOT}/.gitignore"
    echo "✓ Added .relay-locks/ and .screenshots/ to .gitignore"
  fi
fi

echo ""
echo "Done! Next steps:"
echo ""
echo "  1. Edit .devtools.yaml with your project settings"
echo "  2. Add devtools to your PATH:"
echo "     export PATH=\"${DEVTOOLS_ROOT}/bin:\$PATH\""
echo "  3. Or use the full path:"
echo "     ${DEVTOOLS_ROOT}/bin/devtools relay-race"
echo ""
echo "  For git submodule install:"
echo "    git submodule add <repo-url> tools/devtools"
echo "    Then scripts can reference: tools/devtools/bin/relay-race"
