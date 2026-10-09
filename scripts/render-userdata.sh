#!/usr/bin/env bash
# Print cloud-init.sh with the allowed addresses filled in, ready to paste into
# the DigitalOcean "User data" box. By default nothing is written to disk, so
# the addresses never land in the repository.
#
#   scripts/render-userdata.sh                  # allow this network's public IPv4 (/32)
#   scripts/render-userdata.sh 203.0.113.7/32   # allow an explicit CIDR
#   scripts/render-userdata.sh 203.0.113.7/32 198.51.100.9/32   # allow several (e.g. two uplinks)
#   scripts/render-userdata.sh --allow-wide 203.0.113.0/24
#   scripts/render-userdata.sh -o userdata.txt  # write a file (mode 600) instead of stdout
#
# With -o, a path inside this repository must be git-ignored (rendered/ and
# *.userdata are), or the script refuses, so the address cannot be committed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="${here}/../cloud-init.sh"
allow_wide=0
cidrs=()
output=""

while (($# > 0)); do
    case "$1" in
        --allow-wide) allow_wide=1 ;;
        -o | --output)
            if (($# < 2)); then
                echo "$1 needs a file name" >&2
                exit 2
            fi
            output="$2"
            shift
            ;;
        -h | --help)
            sed -n '2,15p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) cidrs+=("$1") ;;
    esac
    shift
done

if ((${#cidrs[@]} == 0)); then
    ip="$(curl -fsS --max-time 10 https://api.ipify.org)"
    cidrs=("${ip}/32")
    echo "Detected public address, allowing ${cidrs[0]}" >&2
fi

check_cidr() {
    local cidr="$1"
    if [[ ! "${cidr}" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]]; then
        echo "Not an IPv4 CIDR: ${cidr}" >&2
        exit 2
    fi
    local octet
    for octet in "${BASH_REMATCH[@]:1:4}"; do
        if ((10#${octet} > 255)); then
            echo "Octet out of range in ${cidr}" >&2
            exit 2
        fi
    done
    local prefix="${BASH_REMATCH[5]}"
    if ((10#${prefix} > 32)); then
        echo "Prefix out of range in ${cidr}" >&2
        exit 2
    fi
    if ((10#${prefix} == 0)); then
        echo "Refusing ${cidr}: it would open the server to everyone." >&2
        exit 2
    fi
    if ((10#${prefix} < 24)) && ((allow_wide == 0)); then
        echo "Refusing ${cidr}: wider than /24. Pass --allow-wide if you mean it." >&2
        exit 2
    fi
}
for cidr in "${cidrs[@]}"; do
    check_cidr "${cidr}"
done
cidr_list="${cidrs[*]}"

if [[ -z "${output}" ]]; then
    sed "s|__ALLOWED_CIDRS__|${cidr_list}|" "${template}"
    exit 0
fi

# Refuse to write a rendered file into the repository unless git ignores it.
if [[ ! -d "$(dirname "${output}")" ]]; then
    echo "Directory does not exist: $(dirname "${output}")" >&2
    exit 2
fi
out_dir="$(cd "$(dirname "${output}")" && pwd)"
out_path="${out_dir}/$(basename "${output}")"
repo_root="$(cd "${here}/.." && pwd)"
if [[ "${out_path}" == "${repo_root}"/* ]] && ! git -C "${repo_root}" check-ignore -q -- "${out_path}"; then
    echo "Refusing to write ${out_path}: inside the repository and not git-ignored." >&2
    echo "Use a name ending in .userdata, a path under rendered/, or a path outside the repository." >&2
    exit 2
fi
(
    umask 077
    sed "s|__ALLOWED_CIDRS__|${cidr_list}|" "${template}" >"${out_path}"
)
echo "Wrote ${out_path} (mode 600). Delete it once the droplet is created." >&2
