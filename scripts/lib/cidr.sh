# shellcheck shell=bash
# Shared CIDR handling for the render scripts.

# Print this network's public IPv4 as a /32.
detect_public_cidr() {
    local ip
    ip="$(curl -fsS --max-time 10 https://api.ipify.org)"
    echo "${ip}/32"
}

# Exit 2 unless the argument is a sane IPv4 CIDR: valid octets and prefix, never
# /0, and nothing wider than /24 unless the second argument is 1.
check_cidr() {
    local cidr="$1" allow_wide="${2:-0}"
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
