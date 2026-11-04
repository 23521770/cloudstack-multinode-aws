# KVM Host 1

Các lệnh dựng KVM Host 1 theo thứ tự, kèm cách kiểm tra.

## Phiên bản

| Thành phần | Phiên bản | Nguồn |
|---|---|---|
| Ubuntu | 24.04 LTS (noble) | AMI lúc launch |
| CloudStack Agent | 4.23.0.0 | repo `deb https://download.cloudstack.org/ubuntu noble 4.23` |
| libvirt / QEMU | 10.0.0 / 8.2.2 | gói mặc định Ubuntu 24.04, đo bằng `virsh version` |
| Java | 17 | cài kèm cloudstack-agent |
| CirrOS (VM thử) | 0.6.2 | |
| AWS CLI | v2, CHƯA ĐO bản cụ thể | kiểm tra bằng `aws --version` |

## Cấu hình máy

| Mục | kvm-host-1 |
|---|---|
| Instance type | m7i-flex.large (2 vCPU, 8 GiB) |
| AMI | Ubuntu Server 24.04 LTS |
| Ổ đĩa | 60 GiB gp3 (đo sau khi launch: ổ root còn trống 56 GiB) |
| Subnet / IP VPC | cloudstack-compute · 10.20.20.11 |
| IP overlay (cloudbr0) | 192.168.56.11 |
| Security group | cloudstack-compute-sg, không public IP |
| Advanced details | Nested virtualization: Enable · Termination protection: Enable |

Lý do chọn m7i-flex.large: xem [aws/network-design.md](../../aws/network-design.md).

## 0. Launch kvm-host-1

Cần có trước: subnet `cloudstack-compute` và 8 rule ở [aws/security-groups.md](../../aws/security-groups.md). *EC2 → Instances → Launch instances*:

1. Name `kvm-host-1`.
2. AMI *Ubuntu Server 24.04 LTS (HVM), SSD Volume Type*, 64-bit (x86).
3. Instance type `m7i-flex.large`.
4. Key pair: key SSH chung của nhóm (không commit file `.pem`).
5. Network: VPC `cloudstack-vpc`, subnet `cloudstack-compute`, *Auto-assign public IP* `Disable`, security group `cloudstack-compute-sg`, *Advanced network configuration → Primary IP* `10.20.20.11`.
6. Storage `60` GiB `gp3`.
7. *Advanced details*: **Nested virtualization** `Enable`, **Termination protection** `Enable`.

Kiểm tra, PowerShell trên laptop:

```powershell
aws ec2 describe-instances --region ap-southeast-1 --filters "Name=tag:Name,Values=kvm-host-1" --query "Reservations[].Instances[].[State.Name,PrivateIpAddress,PublicIpAddress,CpuOptions]"
```

Mong đợi: `running`, `10.20.20.11`, không có public IP, `NestedVirtualization` là `enabled`.

## 1. SSH vào host qua EICE

Chạy trong PowerShell trên laptop:

```powershell
aws ec2-instance-connect ssh --region ap-southeast-1 --instance-id <ID kvm-host-1> --os-user ubuntu --connection-type eice --private-key-file <đường dẫn key.pem>
```

Kiểm tra: dấu nhắc đổi thành `ubuntu@...`.

Việc đầu tiên sau khi vào máy (cloudstack-management phải đang chạy để ping được):

```bash
ip -br a
curl -I --max-time 15 https://archive.ubuntu.com
ping -c3 10.20.10.10
nproc; free -h; df -h /
sudo apt update && sudo apt -y full-upgrade
sudo reboot
```

Kiểm tra: card `enp39s0` có `10.20.20.11/24`, `curl` trả `200` (ra internet qua NAT), ping `0% packet loss`, 2 CPU, 7,6 GiB RAM. Ubuntu gợi ý lên 26.04 thì **không** chạy `do-release-upgrade`.

## 2. Hostname và kiểm tra KVM

Chạy trên kvm-host-1:

```bash
sudo hostnamectl set-hostname kvm-host-1
echo "preserve_hostname: true" | sudo tee /etc/cloud/cloud.cfg.d/99-hostname.cfg
grep -q 'kvm-host-1' /etc/hosts || sudo tee -a /etc/hosts >/dev/null <<'HOSTS'
192.168.56.10 cloudstack-management
192.168.56.11 kvm-host-1
192.168.56.12 kvm-host-2
HOSTS
lscpu | grep -E 'Architecture|Virtualization'
grep -cE 'vmx|svm' /proc/cpuinfo
sudo apt install -y cpu-checker
kvm-ok
```

Kiểm tra: `Virtualization: VT-x`, số đếm `4`, `kvm-ok` in `KVM acceleration can be used`.

## 3. Cài và cấu hình libvirt

Chạy trên kvm-host-1. Cấu hình theo tài liệu *KVM Hypervisor Host Installation* của CloudStack 4.23 cho Ubuntu 22.04 trở lên:

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm ubuntu

grep -q '^listen_tls' /etc/libvirt/libvirtd.conf || \
sudo tee -a /etc/libvirt/libvirtd.conf >/dev/null <<'CONF'
listen_tls = 0
listen_tcp = 0
tls_port = "16514"
tcp_port = "16509"
auth_tcp = "none"
mdns_adv = 0
CONF
sudo sed -i 's/^#\?LIBVIRTD_ARGS=.*/LIBVIRTD_ARGS="--listen"/' /etc/default/libvirtd
grep -q '^LIBVIRTD_ARGS=' /etc/default/libvirtd || \
  echo 'LIBVIRTD_ARGS="--listen"' | sudo tee -a /etc/default/libvirtd
grep -q '^remote_mode' /etc/libvirt/libvirt.conf || \
  echo 'remote_mode="legacy"' | sudo tee -a /etc/libvirt/libvirt.conf
sudo systemctl mask libvirtd.socket libvirtd-ro.socket libvirtd-admin.socket \
  libvirtd-tls.socket libvirtd-tcp.socket

sudo ln -sf /etc/apparmor.d/usr.sbin.libvirtd /etc/apparmor.d/disable/
sudo ln -sf /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/usr.sbin.libvirtd
sudo apparmor_parser -R /etc/apparmor.d/usr.lib.libvirt.virt-aa-helper
sudo sed -i 's/^#\?security_driver *=.*/security_driver = "none"/' /etc/libvirt/qemu.conf
grep -q '^security_driver' /etc/libvirt/qemu.conf || \
  echo 'security_driver = "none"' | sudo tee -a /etc/libvirt/qemu.conf
sudo systemctl restart libvirtd
sudo reboot
```

Kiểm tra, sau khi SSH vào lại:

```bash
grep LIBVIRTD_ARGS /etc/default/libvirtd
grep '^security_driver' /etc/libvirt/qemu.conf
systemctl is-active libvirtd
sudo virsh -c qemu:///system version
sudo aa-status | grep -c libvirt
```

Mong đợi: `LIBVIRTD_ARGS="--listen"`, `security_driver = "none"`, `active`, libvirt 10.0.0 / QEMU 8.2.2, `0`.

## 4. Cài CloudStack Agent 4.23

Chạy trên kvm-host-1:

```bash
echo "deb https://download.cloudstack.org/ubuntu noble 4.23" | \
  sudo tee /etc/apt/sources.list.d/cloudstack.list
wget -O - https://download.cloudstack.org/release.asc | \
  sudo tee /etc/apt/trusted.gpg.d/cloudstack.asc >/dev/null
sudo apt update
sudo apt install -y cloudstack-agent chrony
java -version
dpkg -l cloudstack-agent | tail -1
```

Kiểm tra: Java 17, dòng `ii cloudstack-agent 4.23.0.0...`. Agent chưa chạy cho tới khi host được Add vào CloudStack.

## 5. VM thử nested

Chạy trên kvm-host-1:

```bash
cd /var/lib/libvirt/images
[ -f cirros-0.6.2-x86_64-disk.img ] || sudo wget https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img
[ -f test-vm1.qcow2 ] || sudo qemu-img create -f qcow2 -F qcow2 -b cirros-0.6.2-x86_64-disk.img test-vm1.qcow2 1G
sudo virsh net-start default 2>/dev/null; sudo virsh net-autostart default
sudo virsh dominfo test-vm1 >/dev/null 2>&1 || \
sudo virt-install --name test-vm1 --memory 512 --vcpus 1 \
  --disk path=/var/lib/libvirt/images/test-vm1.qcow2,format=qcow2 \
  --import --os-variant generic --network network=default \
  --graphics none --noautoconsole
sudo virsh list --all
sudo virsh dumpxml test-vm1 | grep -m1 "<domain type"
sudo virsh qemu-monitor-command test-vm1 --hmp 'info kvm'
```

Kiểm tra: `test-vm1 running`, `<domain type='kvm'`, `kvm support: enabled`.

## 6. Overlay cloudbr0 / cloudbr1

File [`kvm/networking/cloud-overlay.sh`](../networking/cloud-overlay.sh) và [`cloud-overlay.service`](../networking/cloud-overlay.service). Chạy trên kvm-host-1 và cloudstack-management, từ thư mục gốc repo; trên Management sửa 3 biến đầu script theo bảng trong file trước:

```bash
sudo install -m 0755 kvm/networking/cloud-overlay.sh /usr/local/sbin/
sudo install -m 0644 kvm/networking/cloud-overlay.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloud-overlay
```

Chỉ trên cloudstack-management, bật gateway và NAT cho overlay:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-cloud.conf
sudo sysctl --system
sudo iptables -t nat -C POSTROUTING -s 192.168.56.0/24 ! -d 192.168.56.0/24 -j MASQUERADE 2>/dev/null || \
  sudo iptables -t nat -A POSTROUTING -s 192.168.56.0/24 ! -d 192.168.56.0/24 -j MASQUERADE
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
sudo iptables -t nat -S POSTROUTING
```

Kiểm tra, trên kvm-host-1:

```bash
ip -br a show cloudbr0
bridge fdb show dev vxlan100 | grep dst
ping -c3 192.168.56.10
ping -c1 -M do -s 1472 192.168.56.10
```

Mong đợi: cloudbr0 `UP` với 192.168.56.11, fdb có `dst 10.20.10.10`, cả 2 lệnh ping thông (lệnh sau là gói 1500 byte, cờ DF).

## 7. NFS

Trên cloudstack-management (cấu hình `/etc/exports` ở [management/nfs-config.example](../../management/nfs-config.example)):

```bash
df -h /
sudo mkdir -p /export/primary /export/secondary
sudo apt install -y nfs-kernel-server
grep -q '^/export ' /etc/exports || \
  echo '/export  10.20.0.0/16(rw,async,no_root_squash,no_subtree_check) 192.168.56.0/24(rw,async,no_root_squash,no_subtree_check)' | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl enable --now nfs-server
sudo exportfs -v
showmount -e localhost
```

Kiểm tra: `/export 10.20.0.0/16,192.168.56.0/24`.

Trên kvm-host-1, mount thử rồi gỡ:

```bash
sudo apt install -y nfs-common
sudo mkdir -p /mnt/test-primary /mnt/test-secondary
sudo mount -t nfs -o vers=4.2 10.20.10.10:/export/primary   /mnt/test-primary
sudo mount -t nfs -o vers=4.2 10.20.10.10:/export/secondary /mnt/test-secondary
df -h /mnt/test-primary /mnt/test-secondary
sudo touch /mnt/test-primary/hello-from-$(hostname) && ls -l /mnt/test-primary
sudo dd if=/dev/zero of=/mnt/test-primary/speed.bin bs=1M count=512 oflag=direct
sudo rm /mnt/test-primary/speed.bin /mnt/test-primary/hello-*
sudo umount /mnt/test-primary /mnt/test-secondary
```

Kiểm tra: `df` hiện 2 dòng `10.20.10.10:/export/...`, file tạo được với owner root, `dd` in tốc độ ghi.

## 8. Cho Management SSH vào host bằng root

Trên cloudstack-management:

```bash
sudo cat /var/lib/cloudstack/management/.ssh/id_rsa.pub
```

Dòng in ra là loại `ecdsa-sha2-nistp256`, dù tên file là `id_rsa.pub`. Đây là public key, không phải bí mật. Trên kvm-host-1, dán nguyên dòng đó vào giữa hai dấu nháy:

```bash
KEY='<nguyên dòng key>'
sudo grep -qF "$KEY" /root/.ssh/authorized_keys || echo "$KEY" | sudo tee -a /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys
```

Kiểm tra, trên cloudstack-management:

```bash
sudo ssh -i /var/lib/cloudstack/management/.ssh/id_rsa -o StrictHostKeyChecking=accept-new root@10.20.20.11 hostname
```

Phải in `kvm-host-1`.

## Kết quả trên kvm-host-1

| Kiểm tra | Kết quả |
|---|---|
| Nested trên instance | `NestedVirtualization: enabled`, loại máy `FreeTierEligible: true` |
| `grep -cE 'vmx\|svm' /proc/cpuinfo` | `4` (2 vCPU, mỗi CPU có dòng *flags* và *vmx flags*) |
| `kvm-ok` | `KVM acceleration can be used` |
| libvirt / QEMU | 10.0.0 / 8.2.2, `virt-host-validate` đạt các mục cần thiết |
| CloudStack Agent | 4.23.0.0, Java 17 |
| VM thử test-vm1 (CirrOS) | `domain type='kvm'`, `kvm support: enabled` |
| Overlay | ping 192.168.56.10 ↔ .11 thông, gói 1500 byte có cờ DF qua được, tự lên sau reboot |
| NFS | mount NFSv4.2 primary và secondary, ghi bằng root được, tốc độ ghi khoảng 1.2 GB/s |
| SSH từ Management | `root@10.20.20.11` bằng System SSH Key thành công |

Card mạng VPC trên m7i-flex tên `enp39s0`, không phải `ens5`. Các script không ghi tên card nên chạy được trên mọi máy.
## Lỗi đã gặp

| Hiện tượng | Nguyên nhân | Cách sửa |
|---|---|---|
| Launch m7i.xlarge không được phép | Tài khoản ở Free plan, loại máy không free tier eligible | Dùng m7i-flex.large (vẫn có nested) |
| `AuthFailure` / `InvalidClientTokenId` khi chạy AWS CLI | Profile `default` dùng key cũ | `aws login --profile <tên> --region ap-southeast-1`, rồi `$env:AWS_PROFILE="<tên>"` |
| Không SSH được vào host qua EICE | Rule outbound của eice-sg tới compute-sg bị nhập port 0 thay vì 22 | Thêm rule TCP 22 (xem `aws/security-groups.md`) |
| Lần SSH đầu sau reboot báo `OSError` | Máy chưa khởi động xong | Đợi thêm 30 giây |
| `grep -cE 'vmx\|svm' /proc/cpuinfo` ra `4` chứ không phải `2` | Mỗi CPU có 2 dòng chứa vmx (*flags* và *vmx flags*) | Bình thường, lớn hơn 0 là có nested |
| `virt-install`: *Failed to query AppArmor policy* | Thiếu `security_driver = "none"` trong `/etc/libvirt/qemu.conf` | Thêm dòng đó (bước 3), rồi `sudo reboot` |
| Lệnh có `-o ens5` hoặc `tcpdump -i ens5` báo không có card | Card trên m7i-flex tên `enp39s0` | Không ghi tên card; dùng `tcpdump -ni any` |
| Ubuntu gợi ý nâng lên 26.04 | | Không chạy `do-release-upgrade`, repo CloudStack dùng bản `noble` (24.04) |
| Key của Management bị dán vào chính máy Management | Mở nhiều cửa sổ SSH, chạy nhầm máy | Gỡ dòng đó, dán lại trên kvm-host-1; nhìn dấu nhắc `ubuntu@kvm-host-1` trước khi dán lệnh |
| Tiếng Việt lỗi font khi xem file trong PowerShell | PowerShell không đọc UTF-8 mặc định | `[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-Content <file> -Encoding UTF8` |
