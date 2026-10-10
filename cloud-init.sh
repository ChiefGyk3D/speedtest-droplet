#!/usr/bin/env bash
# Cloud-init user data for a throwaway iperf3 server on Ubuntu 24.04.
#
# Do not paste this file as it is: scripts/render-userdata.sh fills in
# ALLOWED_CIDRS, the only addresses that may reach SSH and iperf3. An unrendered
# copy refuses to run, so a droplet can never come up open to the internet.
set -euo pipefail

ALLOWED_CIDRS="__ALLOWED_CIDRS__" # one or more IPv4 CIDRs, space separated
IPERF_PORTS="5201 5202"

# Refuse before touching anything if the placeholder was not replaced.
for cidr in ${ALLOWED_CIDRS}; do
    if [[ ! "${cidr}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$ ]]; then
        echo "ALLOWED_CIDRS holds something that is not a rendered IPv4 CIDR: '${cidr}'" >&2
        echo "Render this file with scripts/render-userdata.sh before use." >&2
        exit 1
    fi
    if [[ "${cidr}" == */0 ]]; then
        echo "Refusing ${cidr}: it would open the server to everyone." >&2
        exit 1
    fi
done
if [[ -z "${ALLOWED_CIDRS// /}" ]]; then
    echo "ALLOWED_CIDRS is empty. Render this file with scripts/render-userdata.sh." >&2
    exit 1
fi

exec > >(tee -a /var/log/speedtest-droplet-init.log) 2>&1
echo "speedtest-droplet init started $(date -u +%FT%TZ)"

export DEBIAN_FRONTEND=noninteractive
echo "iperf3 iperf3/start_daemon boolean false" | debconf-set-selections
apt-get update -y
apt-get install -y iperf3 ufw

# Large socket buffers so a single flow can fill a 1 to 2.5 Gbit/s path with
# tens of milliseconds of latency. The congestion control stays at the kernel
# default so results look like what ordinary servers give a client.
cat >/etc/sysctl.d/90-speedtest.conf <<'EOF'
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.core.default_qdisc = fq
EOF
sysctl --system >/dev/null

# One iperf3 server per port, so two clients (or a 2.5 Gbit/s test from two
# hosts) can run at once. iperf3 serves one test at a time per instance.
cat >/etc/systemd/system/iperf3@.service <<'EOF'
[Unit]
Description=iperf3 server on port %i
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/iperf3 --server --port %i
Restart=always
RestartSec=2
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
for port in ${IPERF_PORTS}; do
    systemctl enable --now "iperf3@${port}.service"
done

# Host firewall, in addition to any DigitalOcean cloud firewall.
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
for cidr in ${ALLOWED_CIDRS}; do
    ufw allow from "${cidr}" to any port 22 proto tcp
    for port in ${IPERF_PORTS}; do
        ufw allow from "${cidr}" to any port "${port}" proto tcp
        ufw allow from "${cidr}" to any port "${port}" proto udp
    done
done
ufw --force enable

# Key-only SSH.
cat >/etc/ssh/sshd_config.d/10-speedtest.conf <<'EOF'
PasswordAuthentication no
PermitRootLogin prohibit-password
EOF
# Ubuntu 24.04 starts sshd on demand (ssh.socket), so the service may not be
# running yet; new connections read the drop-in file either way. Check the
# config is valid, and reload only if the service is up.
mkdir -p /run/sshd # sshd -t needs its privilege-separation directory
sshd -t
if systemctl is-active --quiet ssh.service; then
    systemctl reload ssh.service
fi

mkdir -p /var/lib/speedtest-droplet
date -u +%FT%TZ >/var/lib/speedtest-droplet/ready
echo "speedtest-droplet init finished: iperf3 on ports ${IPERF_PORTS}, allowed ${ALLOWED_CIDRS}"
