#!/usr/bin/env bash
# scripts/install-tools.sh
# Idempotent asdf + Kubernetes tooling installer for WSL2 Ubuntu 24.04.
# Installs asdf v0.18 (Go binary), creates ~/.karyon/shell-init.sh for PATH wiring,
# adds asdf plugins, and installs pinned versions from .tool-versions.
#
# Usage:  bash scripts/install-tools.sh
# Safe to re-run — skips steps already done.
# After first run: run 'source ~/.bashrc' or open a new terminal to activate asdf shims.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/preflight-lib.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/preflight-lib.sh"

ASDF_VERSION="v0.18.1"
ASDF_TARBALL_URL="https://github.com/asdf-vm/asdf/releases/download/${ASDF_VERSION}/asdf-${ASDF_VERSION}-linux-amd64.tar.gz"

# ---------------------------------------------------------------------------
# Section 1: Prerequisites (curl, tar)
# ---------------------------------------------------------------------------
section "Prerequisites (curl, tar)"
if have curl && have tar; then
  info "already done, skipping: prerequisites (curl tar)"
else
  sudo apt-get install -y curl tar
  pass "installing: prerequisites (curl tar)"
fi

# ---------------------------------------------------------------------------
# Section 2: asdf binary (H2 fix — standalone from GitHub release tarball)
#
# asdf cannot install itself via its own plugin protocol (chicken/egg problem).
# This section installs the asdf binary DIRECTLY from the GitHub release tarball
# BEFORE any asdf plugin or asdf install calls.
# Idempotent: if /usr/local/bin/asdf already exists at the right version, skip.
# ---------------------------------------------------------------------------
section "asdf binary (${ASDF_VERSION})"
if [[ -x /usr/local/bin/asdf ]] && /usr/local/bin/asdf --version 2>/dev/null | grep -qE "^0\.(1[89]|[2-9])"; then
  info "already done, skipping: asdf ${ASDF_VERSION}"
else
  curl -fsSL "${ASDF_TARBALL_URL}" | sudo tar -xz -C /usr/local/bin asdf
  sudo chmod +x /usr/local/bin/asdf
  pass "installing: asdf ${ASDF_VERSION} to /usr/local/bin/asdf"
fi

# ---------------------------------------------------------------------------
# Section 3: ~/.karyon/shell-init.sh (D-06)
# Creates a diffable, decommissionable PATH artifact.
# asdf v0.18+ (Go rewrite) uses PATH export — not the old ". $HOME/.asdf/asdf.sh" form.
# ---------------------------------------------------------------------------
section "\$HOME/.karyon/shell-init.sh (asdf PATH wiring)"
mkdir -p "${HOME}/.karyon"
INIT_FILE="${HOME}/.karyon/shell-init.sh"
if [[ -f "$INIT_FILE" ]]; then
  info "already done, skipping: ~/.karyon/shell-init.sh"
else
  cat > "$INIT_FILE" <<'SHELL_INIT'
# asdf v0.18+ (Go rewrite) — shims dir takes over from the old ~/.asdf/bin path
# Do not use the old ". $HOME/.asdf/asdf.sh" form — that is for the legacy shell-script version.
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"
SHELL_INIT
  chmod 644 "$INIT_FILE"
  pass "installing: ~/.karyon/shell-init.sh"
fi

# ---------------------------------------------------------------------------
# Section 4: ~/.bashrc sourcing hook (D-06 — idempotent grep guard)
# Appends exactly one sourcing line; grep guard prevents duplicates on re-run.
# ---------------------------------------------------------------------------
section "\$HOME/.bashrc karyon shell-init hook"
# grep for the literal tilde form — the appended line uses ~ not $HOME
# shellcheck disable=SC2088  # tilde in single-quotes is intentional: searching for literal ~ in .bashrc
if grep -qF '~/.karyon/shell-init.sh' "${HOME}/.bashrc" 2>/dev/null; then
  info "already done, skipping: \$HOME/.bashrc karyon shell-init hook"
else
  echo '[ -f ~/.karyon/shell-init.sh ] && source ~/.karyon/shell-init.sh' >> "${HOME}/.bashrc"
  pass "installing: ~/.bashrc karyon shell-init hook"
  info "Run 'source ~/.bashrc' or open a new terminal to activate asdf shims"
fi

# ---------------------------------------------------------------------------
# Section 5: asdf plugins
# Ensure asdf binary is in PATH before running any asdf commands.
# Plugin names from RESEARCH.md §Claude's Discretion #4:
#   kubectl, helm, flux2, k3d, k9s, task, jq, yq (8 plugins)
#   NOTE: flux2 (not flux), yq = mikefarah yq v4
# ---------------------------------------------------------------------------
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:/usr/local/bin:$PATH"

section "asdf plugins"
for plugin in kubectl helm flux2 k3d k9s task jq yq gitleaks; do
  if asdf plugin list 2>/dev/null | grep -qx "$plugin"; then
    info "already done, skipping: asdf plugin ${plugin}"
  else
    asdf plugin add "$plugin"
    pass "installing: asdf plugin ${plugin}"
  fi
done

# ---------------------------------------------------------------------------
# Section 6: tool versions from .tool-versions (D-05 guarded-sections pattern)
#
# IMPORTANT: The iteration SKIPS any line where the tool name is "asdf".
# asdf is installed as a standalone binary in Section 2 above.
# Cannot install asdf via 'asdf install' — asdf cannot install itself via plugin
# protocol (chicken/egg problem). The asdf line in .tool-versions is documentation
# only (records the expected version). Do NOT remove this skip guard.
# ---------------------------------------------------------------------------
section "tool versions (from .tool-versions)"
# Run from repo root so asdf finds .tool-versions
cd "${REPO_ROOT}"
if [[ ! -f .tool-versions ]]; then
  fail ".tool-versions not found at ${REPO_ROOT} — check Plan 01 output"
  exit 1
fi

# Check whether any version pin is missing before calling asdf install.
# asdf install is idempotent but logs nothing useful on a no-op; this guard
# keeps the output consistent with D-05: either "already done, skipping:" or "installing:".
_any_missing=0
while IFS=' ' read -r _tool _ver; do
  [[ -z "$_tool" || "$_tool" == \#* ]] && continue
  # Skip asdf itself: it is installed as a standalone binary in Section 2.
  # asdf cannot install itself via its own plugin protocol — do not pass it to asdf install.
  [[ "$_tool" == "asdf" ]] && continue
  if ! asdf list "$_tool" 2>/dev/null | tr -d ' *' | grep -Fxq "$_ver"; then
    _any_missing=1
    break
  fi
done < .tool-versions

if (( _any_missing == 0 )); then
  info "already done, skipping: tool versions (all pins present)"
else
  # Install each tool individually to provide per-tool feedback.
  # Skip asdf: standalone binary, not managed via asdf plugin protocol.
  while IFS=' ' read -r _tool _ver; do
    [[ -z "$_tool" || "$_tool" == \#* ]] && continue
    # Skip asdf: standalone binary, not managed via asdf plugin protocol.
    [[ "$_tool" == "asdf" ]] && continue
    asdf install "$_tool" "$_ver"
  done < .tool-versions
  pass "installing: tool versions from .tool-versions"
fi

# ---------------------------------------------------------------------------
# Section 7: gitleaks asdf plugin (D-07 / REQ-REPO-04)
# Adds the gitleaks plugin if not present. Tool version pinned in .tool-versions.
# Section 6 above iterates .tool-versions and `asdf install`s gitleaks 8.30.1.
# Plugin source: jmcvetta/asdf-gitleaks (resolves zricethezav/gitleaks redirect
# to gitleaks/gitleaks releases; verified 200 OK against v8.30.1 on 2026-04-28).
# ---------------------------------------------------------------------------
section "asdf plugin gitleaks"
if asdf plugin list 2>/dev/null | grep -qx gitleaks; then
  info "already done, skipping: asdf plugin gitleaks"
else
  asdf plugin add gitleaks
  pass "installing: asdf plugin gitleaks"
fi

# ---------------------------------------------------------------------------
# Section 8: Git core.hooksPath wiring (D-06 / REQ-REPO-04)
# Idempotent: only writes if value differs from "hooks".
# Once set, `git commit` runs hooks/pre-commit instead of .git/hooks/pre-commit.
# This is per-clone configuration; survives `git pull`.
# ---------------------------------------------------------------------------
section "Git core.hooksPath = hooks"
current_hooksPath="$(git -C "$REPO_ROOT" config --local core.hooksPath 2>/dev/null || echo '')"
if [[ "$current_hooksPath" == "hooks" ]]; then
  info "already done, skipping: core.hooksPath = hooks"
else
  git -C "$REPO_ROOT" config --local core.hooksPath hooks
  pass "set: git config --local core.hooksPath hooks"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
section "Summary"
printf "  %s%d passed%s, %s%d warnings%s, %s%d failed%s\n" \
  "$C_GREEN" "$PASS" "$C_RESET" "$C_YELLOW" "$WARN" "$C_RESET" "$C_RED" "$FAIL" "$C_RESET"
if (( FAIL > 0 )); then
  printf "\n%sBlockers:%s\n" "$C_RED" "$C_RESET"
  for m in "${FAIL_MSGS[@]}"; do printf "  - %s\n" "$m"; done
  exit 1
fi
printf "\n%sTool install complete.%s\n" "$C_GREEN" "$C_RESET"
printf "Run: source ~/.bashrc  (or open a new terminal) to activate asdf shims\n"
printf "Verify: command -v kubectl  — should resolve to %s/.asdf/shims/kubectl\n" "$HOME"
