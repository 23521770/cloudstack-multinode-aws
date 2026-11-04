# Security group: rule bổ sung cho KVM host và overlay

8 rule thêm vào 3 security group có sẵn `cloudstack-mgmt-sg`, `cloudstack-compute-sg`, `cloudstack-eice-sg`, để SSH vào KVM host, mount NFS và chạy overlay. Không sửa hay xóa rule cũ, không rule nào mở ra internet.

| Security group | Chiều | Giao thức / port | Nguồn / đích | Mục đích |
|---|---|---|---|---|
| compute-sg | In | TCP 22 | eice-sg | SSH vào host qua EICE |
| compute-sg | In | UDP 4789 | compute-sg | VXLAN giữa các host |
| compute-sg | In | UDP 4789 | mgmt-sg | VXLAN từ Management |
| compute-sg | In | ICMP | mgmt-sg | Ping kiểm tra |
| mgmt-sg | In | TCP 2049 | compute-sg | Host mount NFS |
| mgmt-sg | In | UDP 4789 | compute-sg | VXLAN tới Management |
| mgmt-sg | In | ICMP | compute-sg | Ping kiểm tra |
| eice-sg | Out | TCP 22 | compute-sg | EICE chuyển SSH vào host |

Lệnh thêm, chạy trong PowerShell trên laptop (AWS CLI v2). Mỗi lệnh thêm 1 rule, theo đúng thứ tự trong bảng.

**1. Khai báo ID security group** (thay bằng ID thật, không commit ID):

```powershell
$REGION     = "ap-southeast-1"
$COMPUTE_SG = "<id cloudstack-compute-sg>"
$MGMT_SG    = "<id cloudstack-mgmt-sg>"
$EICE_SG    = "<id cloudstack-eice-sg>"
```

**2. Thêm 8 rule:**

```powershell
# compute-sg: SSH từ EICE
aws ec2 authorize-security-group-ingress --region $REGION --group-id $COMPUTE_SG `
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$EICE_SG,Description=SSH-from-EICE}]"

# compute-sg: VXLAN giữa các host
aws ec2 authorize-security-group-ingress --region $REGION --group-id $COMPUTE_SG `
  --ip-permissions "IpProtocol=udp,FromPort=4789,ToPort=4789,UserIdGroupPairs=[{GroupId=$COMPUTE_SG,Description=VXLAN-hosts}]"

# compute-sg: VXLAN từ Management
aws ec2 authorize-security-group-ingress --region $REGION --group-id $COMPUTE_SG `
  --ip-permissions "IpProtocol=udp,FromPort=4789,ToPort=4789,UserIdGroupPairs=[{GroupId=$MGMT_SG,Description=VXLAN-mgmt}]"

# compute-sg: ping từ Management
aws ec2 authorize-security-group-ingress --region $REGION --group-id $COMPUTE_SG `
  --ip-permissions "IpProtocol=icmp,FromPort=-1,ToPort=-1,UserIdGroupPairs=[{GroupId=$MGMT_SG,Description=ICMP-mgmt}]"

# mgmt-sg: NFS từ host
aws ec2 authorize-security-group-ingress --region $REGION --group-id $MGMT_SG `
  --ip-permissions "IpProtocol=tcp,FromPort=2049,ToPort=2049,UserIdGroupPairs=[{GroupId=$COMPUTE_SG,Description=NFS-from-hosts}]"

# mgmt-sg: VXLAN từ host
aws ec2 authorize-security-group-ingress --region $REGION --group-id $MGMT_SG `
  --ip-permissions "IpProtocol=udp,FromPort=4789,ToPort=4789,UserIdGroupPairs=[{GroupId=$COMPUTE_SG,Description=VXLAN-hosts}]"

# mgmt-sg: ping từ host
aws ec2 authorize-security-group-ingress --region $REGION --group-id $MGMT_SG `
  --ip-permissions "IpProtocol=icmp,FromPort=-1,ToPort=-1,UserIdGroupPairs=[{GroupId=$COMPUTE_SG,Description=ICMP-hosts}]"

# eice-sg: outbound SSH tới host
aws ec2 authorize-security-group-egress --region $REGION --group-id $EICE_SG `
  --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$COMPUTE_SG,Description=SSH-to-compute}]"
```

**3. Kiểm tra:**

```powershell
aws ec2 describe-security-group-rules --region $REGION `
  --filters "Name=group-id,Values=$COMPUTE_SG,$MGMT_SG,$EICE_SG" `
  --query "SecurityGroupRules[?ReferencedGroupInfo].[GroupId,IsEgress,IpProtocol,FromPort,Description]" `
  --output table
```

Mong đợi: mỗi lệnh ở bước 2 trả `"Return": true`; rule đã có thì báo `InvalidPermission.Duplicate`, bỏ qua được. Bảng ở bước 3 có 8 dòng mang các Description trên, nằm cùng các rule có sẵn.

Lý do thêm:

- Lúc kiểm tra, mgmt-sg chưa có TCP 2049, và rule outbound của eice-sg tới compute-sg bị nhập **port 0** thay vì 22 nên EICE không SSH được vào host.
- Các port 1798, 16514, 49152–49216, 5900–6100 trong ghi chú thiết kế **không cần mở** trên security group: traffic đó chạy giữa các IP overlay 192.168.56.x, tức là đã nằm trong gói VXLAN UDP 4789.
- NFS chỉ mở TCP 2049 (NFSv4). `showmount -e 10.20.10.10` từ host không chạy được vì không mở rpcbind 111; mount NFSv4.2 vẫn chạy.
