#!/usr/bin/env bash
# Offline checks for the renderer and the template. No network, no root.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${here}/.."
render="${root}/scripts/render-userdata.sh"
fail=0

check() {
    local name="$1"
    shift
    if "$@"; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name}"
        fail=1
    fi
}

renders_clean() {
    local out
    out="$("${render}" 203.0.113.7/32)" || return 1
    [[ "${out}" == *'ALLOWED_CIDR="203.0.113.7/32"'* ]] || return 1
    [[ "${out}" != *'__ALLOWED_CIDR__'* ]] || return 1
    bash -n <<<"${out}"
}

rejects() {
    ! "${render}" "$@" >/dev/null 2>&1
}

accepts_wide_with_flag() {
    "${render}" --allow-wide 203.0.113.0/16 >/dev/null 2>&1
}

unrendered_template_refuses() {
    local rc
    bash "${root}/cloud-init.sh" >/dev/null 2>&1
    rc=$?
    ((rc == 1))
}

template_has_no_real_address() {
    ! grep -Eq '[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}' "${root}/cloud-init.sh"
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}" "${root}/leak-test.txt" "${root}/ok-test.userdata"' EXIT

writes_file_mode_600() {
    "${render}" 203.0.113.7/32 -o "${tmp}/ud.txt" >/dev/null 2>&1 || return 1
    [[ "$(stat -c %a "${tmp}/ud.txt")" == "600" ]] || return 1
    grep -q 'ALLOWED_CIDR="203.0.113.7/32"' "${tmp}/ud.txt"
}

refuses_unignored_file_in_repo() {
    ! "${render}" 203.0.113.7/32 -o "${root}/leak-test.txt" >/dev/null 2>&1 && [[ ! -e "${root}/leak-test.txt" ]]
}

allows_ignored_file_in_repo() {
    "${render}" 203.0.113.7/32 -o "${root}/ok-test.userdata" >/dev/null 2>&1 && [[ -f "${root}/ok-test.userdata" ]]
}

refuses_missing_directory() {
    ! "${render}" 203.0.113.7/32 -o "${tmp}/nope/ud.txt" >/dev/null 2>&1
}

check "renders a /32 and the output parses" renders_clean
check "-o writes a mode 600 file outside the repo" writes_file_mode_600
check "-o refuses a non-ignored path inside the repo" refuses_unignored_file_in_repo
check "-o allows a git-ignored path inside the repo" allows_ignored_file_in_repo
check "-o refuses a missing directory" refuses_missing_directory
check "rejects 0.0.0.0/0" rejects 0.0.0.0/0
check "rejects a bad octet" rejects 999.1.1.1/32
check "rejects a prefix above 32" rejects 203.0.113.7/33
check "rejects text" rejects not-an-address
check "rejects wider than /24 by default" rejects 203.0.113.0/16
check "accepts wider than /24 with --allow-wide" accepts_wide_with_flag
check "unrendered template refuses to run" unrendered_template_refuses
check "template carries no real address" template_has_no_real_address

exit "${fail}"
