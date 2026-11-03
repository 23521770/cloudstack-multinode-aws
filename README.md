# Apache CloudStack Multi-Node on AWS

## 1. Project Overview

Đồ án nghiên cứu, triển khai và đánh giá hệ thống **Apache CloudStack Multi-Node trên nền tảng Amazon Web Services (AWS)**, sử dụng KVM làm công nghệ ảo hóa để xây dựng môi trường thử nghiệm Infrastructure as a Service (IaaS).

Hệ thống được thiết kế với một CloudStack Management Server và hai KVM Compute Hosts, kết hợp các thành phần mạng, lưu trữ, quản lý máy ảo và tự động hóa thông qua CloudStack REST API.

Ngoài việc triển khai hạ tầng, đồ án tập trung vào kiểm thử chức năng, phân tích cơ chế phân bổ VM, đo lường tài nguyên, benchmark hiệu năng, đánh giá khả năng giao tiếp giữa các host và phân tích chi phí vận hành trên AWS.

### Project Objectives

- Thiết kế và triển khai hạ tầng AWS phục vụ CloudStack.
- Cài đặt CloudStack Management Server và MySQL.
- Thiết lập hai KVM Compute Hosts hỗ trợ nested virtualization.
- Cấu hình Zone, Pod, Cluster, Host và Storage.
- Triển khai và quản lý vòng đời máy ảo.
- Kiểm thử giao tiếp mạng giữa các VM trên các host khác nhau.
- Tích hợp CloudStack REST API để tự động provisioning và cleanup.
- Thu thập CPU, RAM, Storage utilization logs.
- Đánh giá provisioning time, hiệu năng và giới hạn hệ thống.
- Kiểm tra tính khả thi của Live Migration và các kịch bản lỗi.
- Phân tích chi phí AWS và xây dựng báo cáo thực nghiệm.

## 2. System Architecture

Hệ thống được thiết kế trên một AWS VPC gồm các thành phần:

| Component | Role |
|---|---|
| AWS VPC & Subnets | Cung cấp hạ tầng mạng cho các EC2 |
| Management EC2 | Chạy CloudStack Management, MySQL và NFS trong môi trường lab |
| KVM Compute Host 1 | Cung cấp tài nguyên CPU, RAM để chạy guest VM |
| KVM Compute Host 2 | Compute node thứ hai phục vụ multi-host |
| Primary Storage | Lưu trữ disk và volume của VM |
| Secondary Storage | Lưu trữ template, ISO và các dữ liệu phụ trợ |
| Guest Network | Cung cấp kết nối cho các VM |
| CloudStack API | Hỗ trợ quản lý và tự động hóa VM |

Hai KVM hosts được thiết kế chạy cùng loại EC2 hỗ trợ nested virtualization. Hệ thống sử dụng shared storage cho các thử nghiệm phù hợp và đánh giá tính khả thi của live migration.

## 3. Repository Structure

```text
cloudstack-multinode-aws/
│
├── README.md
├── .gitignore
│
├── docs/
│   ├── architecture/
│   ├── deployment-guide/
│   ├── report/
│   └── presentation/
│
├── aws/
│   ├── terraform/
│   ├── network/
│   ├── iam-security/
│   └── cost/
│
├── management/
│   ├── cloudstack/
│   ├── mysql/
│   └── nfs/
│
├── kvm/
│   ├── host1/
│   ├── host2/
│   └── networking/
│
├── cloudstack/
│   ├── infrastructure/
│   ├── templates-offerings/
│   └── vm-lifecycle/
│
├── api/
│   ├── authentication/
│   └── provisioning/
│
├── monitoring/
│   ├── scripts/
│   ├── metrics/
│   └── analysis/
│
└── tests/
    ├── functional/
    ├── networking/
    ├── migration/
    ├── failure/
    └── benchmark/
```

*Đây là cấu trúc dự kiến để quản lý toàn bộ đồ án. Các thư mục và script sẽ được bổ sung theo tiến độ thực tế.*

---

## 4. Directory Descriptions

### `docs/` — Documentation, Architecture & Reports

Chứa các tài liệu nghiên cứu, thiết kế hệ thống, hướng dẫn triển khai, báo cáo và nội dung thuyết trình.

- `architecture/`: Sơ đồ kiến trúc AWS, CloudStack, network và storage.
- `deployment-guide/`: Hướng dẫn cài đặt và cấu hình từng thành phần.
- `report/`: Báo cáo đồ án gồm 6 chương theo phân công nhóm.
- `presentation/`: Slide thuyết trình, kịch bản demo và tài liệu minh chứng.

### `aws/` — AWS Infrastructure & Cost Management

Chứa cấu hình và tài liệu quản lý hạ tầng AWS phục vụ triển khai CloudStack.

- `terraform/`: Cấu hình Infrastructure as Code bằng Terraform, bao gồm skeleton và các thành phần được tự động hóa nếu đã triển khai.
- `network/`: Thiết kế VPC, subnet, route table, gateway và network connectivity.
- `iam-security/`: IAM, permissions, Security Groups và các chính sách kiểm soát truy cập.
- `cost/`: AWS Budget, bảng ước tính chi phí, cost audit và checklist cleanup tài nguyên.

### `management/` — CloudStack Management Server & Storage

Chứa cấu hình, script cài đặt và tài liệu vận hành các dịch vụ trên Management EC2.

- `cloudstack/`: Triển khai CloudStack Management Server, kiểm tra service và giao diện quản trị.
- `mysql/`: Cài đặt, cấu hình và kiểm tra MySQL cho CloudStack.
- `nfs/`: Thiết lập NFS Server, Primary Storage và Secondary Storage trong môi trường lab.

### `kvm/` — KVM Hypervisors & Host Networking

Chứa các script và tài liệu cấu hình hai KVM Compute Hosts.

- `host1/`: Cài đặt KVM, QEMU, libvirt, kiểm tra nested virtualization và CloudStack Agent trên Host 1.
- `host2/`: Triển khai KVM Host 2, cấu hình CloudStack Agent và kiểm tra tương thích.
- `networking/`: Cấu hình Linux bridges, guest networking và giải pháp bridge/overlay phù hợp với môi trường AWS.

### `cloudstack/` — Infrastructure & Virtual Machine Management

Chứa cấu hình hạ tầng logic của CloudStack và quy trình quản lý máy ảo.

- `infrastructure/`: Cấu hình Zone, Pod, Cluster, Host, Primary và Secondary Storage.
- `templates-offerings/`: Chuẩn bị VM template, service offering và disk offering.
- `vm-lifecycle/`: Thao tác Deploy, Start, Stop, Reboot, Destroy và phân tích VM scheduling.

### `api/` — CloudStack REST API & Automation

Chứa mã nguồn thực hiện kết nối CloudStack API và tự động hóa việc quản lý tài nguyên.

- `authentication/`: Xử lý API key, secret key, request signing và xác thực API.
- `provisioning/`: Python scripts tự động tạo VM, theo dõi tác vụ, quản lý VM và thực hiện cleanup an toàn, có thể chạy lặp lại mà không tạo trùng tài nguyên (idempotent).

### `monitoring/` — Resource Utilization & Performance Monitoring

Chứa công cụ thu thập và phân tích tài nguyên của hệ thống.

- `scripts/`: Script ghi nhận CPU, RAM, Storage và các thông số hoạt động.
- `metrics/`: Dữ liệu đo đạc và log đã được xử lý, loại bỏ thông tin nhạy cảm.
- `analysis/`: Biểu đồ, thống kê và phân tích mức sử dụng tài nguyên.

### `tests/` — System Testing & Performance Evaluation

Chứa các bài kiểm thử chức năng, mạng, hiệu năng và khả năng phục hồi.

- `functional/`: Kiểm thử VM lifecycle, console và các chức năng CloudStack.
- `networking/`: Ping, iperf3 và thử nghiệm giao tiếp VM-VM cross-host.
- `migration/`: Kiểm tra tính khả thi của Live Migration và ghi nhận kết quả hoặc giới hạn kỹ thuật.
- `failure/`: Thử nghiệm network failure, host/node failure và storage failure.
- `benchmark/`: Đo provisioning time, benchmark tài nguyên, tổng hợp kết quả và biểu đồ.

---

## 5. Project Milestones

| Phase | Main Deliverables |
|---|---|
| W1–W2 | Thiết kế kiến trúc AWS, kiểm tra chi phí và tương thích KVM |
| W3–W4 | Triển khai EC2, Management, MySQL, KVM Hosts, NFS và CloudStack Agents |
| W5 | Zone, Pod, Cluster, Add Hosts, Templates và Guest VM |
| W6 | VM Lifecycle, Scheduler Analysis, Cross-host Networking và REST API |
| W7 | Resource Monitoring, Python Automation và Live Migration feasibility |
| W8 | Functional Testing, Benchmark, Failure Testing và Cost Audit |
| W9 | Hoàn thành báo cáo 6 chương, demo và cleanup AWS |

## 6. Testing & Acceptance Criteria

Hệ thống được đánh giá qua các mốc nghiệm thu chính:

- **Gate 0:** Kiểm tra giá, ngân sách, quota trước khi chạy AWS.
- **Gate 1:** Hai KVM Hosts hỗ trợ nested virtualization.
- **Gate 2:** CloudStack UI hoạt động, hai KVM Hosts Up, NFS khả dụng.
- **Gate 3:** Tạo và quản lý được Guest VM.
- **Gate 4:** Hai Guest VM trên các hosts khác nhau giao tiếp được.
- **Gate 5:** Python provisioning và cleanup thông qua API.
- **Gate 6:** Live Migration thành công hoặc có phân tích giới hạn được kiểm chứng.
- **Gate 7:** Mô phỏng lỗi host, đo khả năng phát hiện và phục hồi.
- **Gate 8:** Báo cáo 6 chương, tài liệu, slide và demo hoàn chỉnh.

Các mục Gate 5–7 thuộc nhóm nâng cao theo kế hoạch nghiệm thu; kết quả sẽ được cập nhật dựa trên thử nghiệm thực tế.

## 7. Team Responsibilities

| Member | Responsibilities |
|---|---|
| Vân | AWS architecture, Management, MySQL, Zone/Pod/Cluster, VM Lifecycle, Scheduler, Monitoring, Functional Test, Chapters 1–2 |
| Mai | AWS Networking, NFS, KVM Host 1, Guest Networking, Cross-host Testing, Live Migration, Failure Testing, Chapters 3–4 |
| Đoan | IAM, Budget, Terraform, KVM Host 2, Template/Offering, REST API, Python Automation, Benchmark, AWS Cost Audit, Chapters 5–6 |

## 8. Security & Cost Considerations

- Không commit AWS credentials, API secrets, SSH private keys hoặc mật khẩu vào repository.
- Sử dụng file cấu hình mẫu để hướng dẫn thiết lập môi trường.
- Kiểm soát truy cập EC2 và MySQL bằng Security Groups phù hợp.
- Theo dõi chi phí bằng AWS Budgets và Cost Explorer.
- Tắt tài nguyên khi không sử dụng và kiểm tra EBS, NAT Gateway, IP, snapshot còn tồn tại.
- Môi trường lab không được mặc định xem là High Availability.

## 9. References

- [Apache CloudStack Documentation](https://docs.cloudstack.apache.org/)
- [AWS Documentation](https://docs.aws.amazon.com/)
- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Ubuntu Server Documentation](https://documentation.ubuntu.com/server/)
