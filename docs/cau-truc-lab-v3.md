# Cấu trúc lab v3 — một môi trường scoped exposure

## 1. Mục đích và phạm vi

Lab v3 vận hành một môi trường Kubernetes duy nhất: namespace
`ai-cve-lab-exposed`. Môi trường này giữ các workload có chức năng nghiệp vụ
và bổ sung các canary vô hại để quan sát ranh giới runtime. Nó không phải bản
vá, không dùng bí mật thật và không mô phỏng quyền node hoặc quyền quản trị
cụm.

Ba trường hợp nghiên cứu vẫn độc lập:

| Trường hợp | Workload | Ranh giới được quan sát |
|---|---|---|
| Beifong boundary model | `beifong-exposed` | Request HTTP, filesystem và phạm vi dữ liệu media/container được mount |
| GitHub MCP observation adapter | `github-mcp-exposed` + `github-credential-sink` | Ownership credential theo phiên và egress nội bộ của workload |
| Paperclip v0.3.1 | `paperclip-exposed` | Authority của agent key, tiến trình server và execution workspace |

`exposed` chỉ là tên của layout thí nghiệm: workload nhận canary tổng hợp để
đo phạm vi. Nó không có nghĩa là một bản hardened, không cấp đặc quyền host và
không biến một lỗi logic ứng dụng thành lỗi Kubernetes.

## 2. Kiến trúc chạy thực tế

```text
Browser / Burp / curl trên 127.0.0.1
      │
      ├── 19091 → Service beifong-exposed → Pod Beifong
      ├── 19501 → Service github-mcp-exposed → Pod GitHub MCP adapter
      ├── 19580 → Service github-credential-sink → Pod sink nội bộ
      └── 19310 → Service paperclip-exposed → Pod Nginx + Paperclip server

Minikube profile ai-cve-lab (Docker driver)
      └── namespace ai-cve-lab-exposed
            ├── ServiceAccount riêng, automount token = false
            ├── ConfigMap runtime và Nginx proxy nội bộ
            ├── Secret boundary-canaries (chỉ dữ liệu LAB vô hại)
            └── NetworkPolicy giới hạn egress của GitHub adapter
```

Port-forward chỉ lắng nghe `127.0.0.1`; Service Kubernetes không được công bố
ra mạng ngoài máy thực hành. Không có `hostPath`, Docker socket, Pod
`privileged`, node credential hay API key thật trong manifest.

## 3. Công nghệ

| Lớp | Công nghệ / vai trò |
|---|---|
| Host | Windows 11, Docker Desktop với WSL 2 backend |
| Cụm | Minikube dùng Docker driver, một control-plane node |
| Điều phối | Kubernetes Deployment, Service, ServiceAccount, Secret, ConfigMap, NetworkPolicy và `emptyDir` |
| Beifong model | Python/FastAPI; giao diện podcast phục vụ qua workload lab |
| GitHub MCP adapter | Python/Streamlit; sink nội bộ ghi nhãn và hash, không lưu credential thô |
| Paperclip | Paperclip v0.3.1 Node.js + React; Nginx sidecar proxy loopback |
| Quan sát | `kubectl`, cURL/Burp, JSON evidence hash-only và trạng thái runtime |

## 4. Cấu trúc thư mục cần dùng

```text
D:\daihoc\Nam4\Doan\lab\
├── README.md
├── startlap.txt
├── scripts\
│   ├── 00-lab-env.ps1
│   ├── 10-setup-ai-cve-lab.ps1
│   ├── 41-capture-beifong-k8s-boundary.ps1
│   ├── 42-capture-github-mcp-k8s-boundary.ps1
│   ├── 43-test-github-mcp-networkpolicy.ps1
│   ├── 44-check-paperclip-scope-marker.ps1
│   ├── 90-start-ai-cve-lab.ps1
│   ├── 91-status-ai-cve-lab.ps1
│   ├── 92-redeploy-ai-cve-lab.ps1
│   ├── 93-reset-active-lab.ps1
│   ├── 94-capture-ch3-run-state.ps1
│   ├── 95-seal-ch3-run-evidence.ps1
│   └── 99-stop-ai-cve-lab.ps1
├── k8s\exposed\
│   ├── 00-base.yaml
│   ├── 01-workloads.yaml
│   └── 02-networkpolicy.yaml
├── images\                         # Dockerfile và adapter/fixture của lab
├── sources\                        # mã nguồn upstream dùng để đối chiếu
├── evidence\campaigns\             # Campaign/Run baseline và evidence đã seal
├── docs\
│   ├── chapter-3-final-experiment-plan.md
│   └── lab-v3-boundary-scenarios.md
└── _state\                          # Minikube, KUBECONFIG và port-forward cục bộ
```

Các manifest, image, script và evidence của các layout trước đã được loại khỏi
workspace. Evidence mới chỉ được tạo trong
`evidence/campaigns/<CampaignId>/<RunId>`.

## 5. Kubernetes manifest đang chạy

### 5.1 `k8s/exposed/00-base.yaml`

Manifest nền tảng tạo namespace, bốn ServiceAccount riêng và đặt
`automountServiceAccountToken: false`. ConfigMap `ai-lab-runtime-config` đặt
`LAB_MODE=exposed` và địa chỉ nội bộ của credential sink.

Secret `boundary-canaries` chỉ có hai chuỗi nhận diện LAB:

| Canary | Mount | Vai trò |
|---|---|---|
| `beifong-outside-audio.txt` | `/var/run/lab-canary` trong Beifong | Kiểm tra rõ phạm vi tệp ngoài vùng audio |
| `paperclip-mount-scope.txt` | `/var/run/lab-canary` trong Paperclip | Kiểm tra read scope của process Paperclip |

Giá trị của các canary không phải dữ liệu người dùng, token hay secret vận hành.

### 5.2 `k8s/exposed/01-workloads.yaml`

| Deployment / Service | Image / port | Cấu hình đáng chú ý |
|---|---|---|
| `beifong-exposed` | `lab/beifong-boundary-model:chapter3-v1`, 7000/80 | Mount canary read-only; audio demo nằm trong vùng phục vụ hợp lệ |
| `github-mcp-exposed` | `lab/github-mcp-vuln-observer:chapter3-boundary-v2`, 8501/80 | Chỉ dùng adapter quan sát local, gửi dữ liệu giả lập tới sink nội bộ |
| `github-credential-sink` | `lab/github-credential-sink:chapter3-boundary-v1`, 8080/8080 | Chạy UID/GID 10001, root filesystem read-only, caps drop ALL, `/tmp` `emptyDir` |
| `paperclip-exposed` | `lab/paperclip-v0.3.1-ui-lab:chapter3-v1` + `nginx:1.27-alpine`, 3101/80 | Paperclip server v0.3.1 với overlay UI lab bật Process adapter; có `/paperclip` và worktree `emptyDir`; canary read-only trong container server |

Paperclip có hai container trong một Pod: Nginx nhận request qua port 3101 và
proxy loopback tới server Paperclip port 3100. `emptyDir` đồng nghĩa Company,
Agent và Project chỉ tồn tại trong vòng đời Pod; nó là fixture tái lập, không
phải database production.

### 5.3 `k8s/exposed/02-networkpolicy.yaml`

NetworkPolicy áp dụng riêng cho `github-mcp-exposed`: egress chỉ được phép đến
credential sink trong namespace và DNS. Đây là ranh giới quan sát network,
không phải biện pháp khắc phục process-global state trong adapter.

## 6. Chạy và kiểm tra

Khởi tạo sau khi Docker Desktop đã ở trạng thái Running:

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\10-setup-ai-cve-lab.ps1
.\scripts\90-start-ai-cve-lab.ps1
```

Khởi động hằng ngày:

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\90-start-ai-cve-lab.ps1
.\scripts\91-status-ai-cve-lab.ps1
```

Làm sạch toàn bộ **runtime state của layout v3** trước một lần chụp mới:

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\93-reset-active-lab.ps1
```

Script này tái tạo riêng namespace `ai-cve-lab-exposed`, làm rỗng event sink
và xóa direct evidence sinh ra ở `evidence\boundary-v3`. Nó không xóa source,
image, manifest, evidence đã seal tại `evidence\campaigns`, hoặc Paperclip
khác ở `http://127.0.0.1:3100/`.

Các URL cần dùng:

| Ứng dụng | URL loopback |
|---|---|
| Beifong | `http://127.0.0.1:19091/` |
| GitHub MCP adapter | `http://127.0.0.1:19501/` |
| Credential sink hash-only | `http://127.0.0.1:19580/events` |
| Paperclip | `http://127.0.0.1:19310/` |

Mỗi Run ID bắt đầu sau reset bằng baseline không nhạy cảm:

```powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId CH3-20261014 -RunId CH3-<CASE>-001 `
  -Checkpoint baseline -RequireClean
```

Các capture scoped, NetworkPolicy measurement và seal SHA-256 được thực hiện
theo `docs\lab-v3-boundary-scenarios.md`.

## 7. Diễn giải đúng kết quả

* Beifong boundary model dùng handler `filename:path`; campaign baseline khóa
  commit, hash handler/Dockerfile và image runtime để kết luận đúng build đã
  đo. Không suy rộng sang build không có trong evidence đó.
* GitHub MCP dùng adapter và sink thay thế để quan sát owner/requester dưới
  dạng hash; không được kết luận GitHub, OpenAI hay MCP server thật nhận token.
* Paperclip evidence chỉ kết luận về principal, process và volume trong Pod;
  marker worktree không chứng minh node escape, Docker socket hoặc Kubernetes
  API access.

Mỗi kết luận trong báo cáo phải nối được phiên bản nguồn → manifest/image →
principal → run ID → quan sát runtime. Ảnh UI hoặc HTTP status đơn lẻ không
đủ làm kết luận bảo mật.
