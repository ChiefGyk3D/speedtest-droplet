#!/usr/bin/env bash
# Print the DigitalOcean cloud-firewall rules for the test droplets, with TCP and
# UDP both allowed on the iperf3 ports, plus a ready-to-run doctl command. Nothing
# is written to disk or sent anywhere; paste the output where you create the
# droplets, and tag them speedtest-droplet so the firewall applies at creation.
#
#   scripts/render-cloud-firewall.sh                       # this network's public IPv4
#   scripts/render-cloud-firewall.sh 203.0.113.7/32 198.51.100.9/32
#   scripts/render-cloud-firewall.sh --allow-wide 203.0.113.0/24
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/cidr.sh
source "${here}/lib/cidr.sh"
allow_wide=0
cidrs=()
tag="speedtest-droplet"

while (($# > 0)); do
    case "$1" in
        --allow-wide) allow_wide=1 ;;
        -h | --help)
            sed -n '2,9p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) cidrs+=("$1") ;;
    esac
    shift
done

if ((${#cidrs[@]} == 0)); then
    cidrs=("$(detect_public_cidr)")
    echo "Detected public address, allowing ${cidrs[0]}" >&2
fi
for cidr in "${cidrs[@]}"; do
    check_cidr "${cidr}" "${allow_wide}"
done
sources="${cidrs[*]}"

cat <<TXT
== Console: Networking, Firewalls, Create Firewall, Inbound Rules
   SSH          TCP  22          sources: ${sources}
   Custom       TCP  5201-5202   sources: ${sources}
   Custom       UDP  5201-5202   sources: ${sources}
   Outbound: leave the defaults (all TCP, UDP and ICMP).
   Apply to Droplets: by tag "${tag}" (add the tag when you create each droplet).

== doctl (run once; droplets tagged ${tag} are covered as they are created)
doctl compute firewall create --name ${tag} --tag-names ${tag} \\
TXT
printf '  --inbound-rules "'
first=1
for cidr in "${cidrs[@]}"; do
    for rule in "tcp,ports:22" "tcp,ports:5201-5202" "udp,ports:5201-5202"; do
        ((first)) || printf ' '
        first=0
        printf 'protocol:%s,address:%s' "${rule}" "${cidr}"
    done
done
printf '" \\\n'
cat <<'TXT'
  --outbound-rules "protocol:tcp,ports:all,address:0.0.0.0/0,address:::/0 protocol:udp,ports:all,address:0.0.0.0/0,address:::/0 protocol:icmp,address:0.0.0.0/0,address:::/0"
TXT
