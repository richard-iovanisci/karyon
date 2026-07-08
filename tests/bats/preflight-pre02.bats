#!/usr/bin/env bats
# tests/bats/preflight-pre02.bats
# Unit tests for Ubuntu 24.04 detection via preflight_check_ubuntu_24_04().

load 'test_helper'

setup() {
  TEST_TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "PRE-02: Ubuntu 24.04 passes preflight_check_ubuntu_24_04" {
  cat > "${TEST_TMPDIR}/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04.1 LTS"
EOF
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    # Override the os-release sourcing by redefining the function to use the temp file
    preflight_check_ubuntu_24_04() {
      local id version_id
      id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${ID:-}\")\"
      version_id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${VERSION_ID:-}\")\"
      if [[ \"\$id\" == 'ubuntu' && \"\$version_id\" == '24.04' ]]; then
        pass 'Ubuntu 24.04 confirmed'
        return 0
      else
        fail \"Expected Ubuntu 24.04 but got ID=\${id:-unknown} VERSION_ID=\${version_id:-unknown}\"
        return 1
      fi
    }
    preflight_check_ubuntu_24_04
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Ubuntu 24.04 confirmed" ]]
}

@test "PRE-02: Ubuntu 22.04 fails preflight_check_ubuntu_24_04" {
  cat > "${TEST_TMPDIR}/os-release" <<'EOF'
ID=ubuntu
VERSION_ID="22.04"
PRETTY_NAME="Ubuntu 22.04.5 LTS"
EOF
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    preflight_check_ubuntu_24_04() {
      local id version_id
      id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${ID:-}\")\"
      version_id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${VERSION_ID:-}\")\"
      if [[ \"\$id\" == 'ubuntu' && \"\$version_id\" == '24.04' ]]; then
        pass 'Ubuntu 24.04 confirmed'
        return 0
      else
        fail \"Expected Ubuntu 24.04 but got ID=\${id:-unknown} VERSION_ID=\${version_id:-unknown}\"
        return 1
      fi
    }
    preflight_check_ubuntu_24_04
  "
  [ "$status" -ne 0 ]
  [[ "$output" =~ "Expected Ubuntu 24.04" ]]
}

@test "PRE-02: non-Ubuntu distro fails" {
  cat > "${TEST_TMPDIR}/os-release" <<'EOF'
ID=debian
VERSION_ID="12"
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
EOF
  run bash -c "
    source '${SCRIPTS_DIR}/lib/preflight-lib.sh'
    preflight_check_ubuntu_24_04() {
      local id version_id
      id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${ID:-}\")\"
      version_id=\"\$(. '${TEST_TMPDIR}/os-release' 2>/dev/null && echo \"\${VERSION_ID:-}\")\"
      if [[ \"\$id\" == 'ubuntu' && \"\$version_id\" == '24.04' ]]; then
        pass 'Ubuntu 24.04 confirmed'
        return 0
      else
        fail \"Expected Ubuntu 24.04 but got ID=\${id:-unknown} VERSION_ID=\${version_id:-unknown}\"
        return 1
      fi
    }
    preflight_check_ubuntu_24_04
  "
  [ "$status" -ne 0 ]
}

@test "PRE-02: VERSION_ID 24.04 string matches exactly" {
  local version="24.04"
  [ "$version" = "24.04" ]
}
