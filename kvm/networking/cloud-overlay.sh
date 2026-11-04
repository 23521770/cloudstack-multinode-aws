#!/bin/bash
# VXLAN unicast overlay cho CloudStack trên AWS.
# Tạo cloudbr0 (VNI 100) và cloudbr1 (VNI 200), nối tới các node còn lại
# qua IP VPC bằng UDP 4789. Mỗi máy chỉ đổi 3 biến đầu:
#
#   Máy                    LOCAL_IP     PEERS                      BR0_ADDRS
#   cloudstack-management  10.20.10.10  "10.20.20.11 10.20.20.12"  "192.168.56.10/24 192.168.56.1/24"
#   kvm-host-1             10.20.20.11  "10.20.10.10 10.20.20.12"  "192.168.56.11/24"
#   kvm-host-2 (dự kiến)   10.20.20.12  "10.20.10.10 10.20.20.11"  "192.168.56.12/24"
#
# Cài (từ thư mục gốc repo):
#       sudo install -m 0755 kvm/networking/cloud-overlay.sh /usr/local/sbin/
#       sudo install -m 0644 kvm/networking/cloud-overlay.service /etc/systemd/system/
#       sudo systemctl daemon-reload && sudo systemctl enable --now cloud-overlay
# Kiểm tra: ip -br a show cloudbr0 ; ping -c3 192.168.56.10
LOCAL_IP=10.20.20.11                  # IP VPC của chính máy này
PEERS="10.20.10.10 10.20.20.12"       # IP VPC của các node còn lại
BR0_ADDRS="192.168.56.11/24"          # IP overlay của máy này

mkbr() {  # mkbr <bridge> <vni> <địa chỉ...>
  local br=$1 vni=$2; shift 2
  ip link show "$br" >/dev/null 2>&1 || ip link add "$br" type bridge
  ip link show "vxlan$vni" >/dev/null 2>&1 || \
    ip link add "vxlan$vni" type vxlan id "$vni" dstport 4789 local "$LOCAL_IP"
  ip link set "vxlan$vni" mtu 1500 master "$br" up
  for p in $PEERS; do
    bridge fdb append 00:00:00:00:00:00 dev "vxlan$vni" dst "$p" 2>/dev/null || true
  done
  ip link set "$br" mtu 1500 up
  for a in "$@"; do ip addr replace "$a" dev "$br"; done
}
mkbr cloudbr0 100 $BR0_ADDRS
mkbr cloudbr1 200
