# Thiết kế mạng: subnet KVM và overlay cho CloudStack

Xây trên VPC `cloudstack-vpc` 10.20.0.0/16 (ap-southeast-1) với NAT Gateway, EICE và security group có sẵn.

## Subnet cloudstack-compute

| Mục | Giá trị |
|---|---|
| CIDR | 10.20.20.0/24 |
| AZ | ap-southeast-1a |
| Route table | `cloudstack-private-rt` (ra internet qua NAT Gateway) |
| Public IP | Không cấp |
| Chứa | kvm-host-1 (10.20.20.11), kvm-host-2 dự kiến (10.20.20.12) |

Các bước đã làm trên Console:

1. *VPC → Subnets → Create subnet*: VPC `cloudstack-vpc`, tên `cloudstack-compute`, AZ `ap-southeast-1a`, CIDR `10.20.20.0/24`.
2. Kiểm tra *Auto-assign public IPv4 address* của subnet là `No`.
3. *Route tables* → `cloudstack-private-rt` → *Subnet associations* → *Edit subnet associations* → tick thêm `cloudstack-compute` (giữ cloudstack-private) → *Save associations*.

Kiểm tra: tab *Routes* của `cloudstack-private-rt` có `10.20.0.0/16 → local` và `0.0.0.0/0 → nat-…`; tab *Subnet associations* có 2 subnet.

## Chọn loại EC2 cho KVM

EC2 hỗ trợ nested virtualization trên instance thường dòng Intel thế hệ 7 và 8 (M7i, M7i-flex, C7i, R7i, M8i…), không cần `.metal`. Tài khoản nhóm ở Free plan nên không launch được m7i.xlarge; **m7i-flex.large** (2 vCPU, 8 GiB) vừa có nested vừa free tier eligible, nên được chọn. Hai host trong một cluster phải cùng loại CPU, nên Host 2 cũng dùng m7i-flex.large.

Lệnh kiểm tra đã chạy (PowerShell trên laptop, AWS CLI v2):

```powershell
aws ec2 describe-instance-types --region ap-southeast-1 --instance-types m7i-flex.large --query "InstanceTypes[].[InstanceType,FreeTierEligible,ProcessorInfo.SupportedFeatures]"
```

Kết quả: `m7i-flex.large`, `true`, có `nested-virtualization`. kvm-host-1 sau khi launch có `NestedVirtualization: enabled`.

## Overlay VXLAN

**Vấn đề.** VPC của AWS chỉ chuyển gói có MAC và IP do AWS cấp. System VM (SSVM, CPVM, Virtual Router) và VM khách do CloudStack tạo có MAC/IP riêng nên bị VPC bỏ. Không thể bridge thẳng card VPC vào `cloudbr0` như máy vật lý (làm vậy còn mất SSH).

**Cách làm.** Tạo mạng L2 riêng 192.168.56.0/24 giữa các node bằng **VXLAN unicast**: mỗi node đóng gói khung Ethernet vào UDP 4789 gửi tới IP VPC của node kia. VPC chỉ thấy gói UDP bình thường, kể cả giữa 2 subnet. Không cần multicast, Transit Gateway hay tắt Source/Destination check.

```text
  cloudstack-private 10.20.10.0/24  |  cloudstack-compute 10.20.20.0/24
+-------------------------+  +-------------------------+  +-------------------------+
| cloudstack-management   |  | kvm-host-1              |  | kvm-host-2 (dự kiến)    |
| VPC      10.20.10.10    |  | VPC      10.20.20.11    |  | VPC      10.20.20.12    |
| cloudbr0 192.168.56.10  |  | cloudbr0 192.168.56.11  |  | cloudbr0 192.168.56.12  |
|          192.168.56.1 gw|  | cloudbr1 (guest)        |  | cloudbr1 (guest)        |
+------------+------------+  +------------+------------+  +------------+------------+
             +=========== VXLAN overlay (UDP 4789 qua card VPC) =======+
                   VNI 100 -> cloudbr0    VNI 200 -> cloudbr1
```

| Bridge | VNI | Traffic dự kiến |
|---|---|---|
| `cloudbr0` | 100 | Management, Storage, Public |
| `cloudbr1` | 200 | Guest (VLAN) |

- **MTU:** VPC có MTU 9001 (tài liệu AWS), header VXLAN trên IPv4 thêm 50 byte (RFC 7348), nên overlay để 1500. Đã đo: gói 1500 byte cờ DF đi qua.
- **Gateway và NAT:** cloudstack-management giữ thêm IP 192.168.56.1, bật `ip_forward` và NAT (MASQUERADE) dải 192.168.56.0/24, để system VM sau này ra internet qua NAT Gateway.
- **Card mạng:** trên m7i-flex tên `enp39s0`, không phải `ens5`. Script và rule NAT không ghi tên card.

Script: [kvm/networking/cloud-overlay.sh](../kvm/networking/cloud-overlay.sh) (Management và Host 1). Lệnh cài và lệnh NAT ở [kvm/host1/README.md](../kvm/host1/README.md).

**Kết quả trên AWS**, giữa cloudstack-management và kvm-host-1: ping hai chiều thông, gói 1500 byte có cờ DF đi qua không phân mảnh, overlay tự lên lại sau reboot.

## Đề xuất dải IP cho Zone

Do overlay, Pod và Public dùng dải 192.168.56.x thay vì 10.20.20.x như nháp ban đầu.

| Dải | Giá trị đề xuất |
|---|---|
| Pod (system VM) | 192.168.56.50 – .99, gateway 192.168.56.1 |
| Public range | 192.168.56.100 – .149, gateway 192.168.56.1, untagged |
| Guest VLAN | 100 – 200 trên cloudbr1 |
| Host 1 khi Add Host | 192.168.56.11 |
