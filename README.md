# AI CVE Kubernetes Lab — v3

Lab này phục vụ Chương III của đồ án: quan sát ba ranh giới bảo mật độc lập
trong một cụm Minikube cục bộ. Layout thực thi duy nhất là namespace
`ai-cve-lab-exposed`; không có chain liên ứng dụng, không có namespace
`vulnerable`/`hardened`, không dùng token thật và không cấp quyền node hoặc
cluster cho workload.

## Ba trường hợp

| Trường hợp | Thành phần | Kết quả được quan sát |
|---|---|---|
| Beifong | `beifong-exposed` | HTTP đọc canary ngoài thư mục nghiệp vụ, nhưng chỉ trong filesystem Pod đã được mount. |
| GitHub MCP | adapter Streamlit + `github-credential-sink` | Credential giả lập bị dùng lại giữa các phiên qua trạng thái `os.environ`; sink chỉ lưu fingerprint. |
| Paperclip | Paperclip v0.3.1 + proxy Nginx | Cấu hình agent và marker vô hại trong `emptyDir` workspace, có giới hạn principal/run riêng. |

Các kết luận chính xác, Campaign/Run ID và giới hạn diễn giải nằm trong
[`docs/chapter-3-final-experiment-plan.md`](docs/chapter-3-final-experiment-plan.md).
Hướng dẫn thao tác từng bước nằm trong
[`docs/lab-v3-boundary-scenarios.md`](docs/lab-v3-boundary-scenarios.md).
Runbook ngắn theo từng lỗi, dùng trực tiếp để thu evidence cho bản nộp, nằm ở
[`docs/lab-v3-official-report-runbook.md`](docs/lab-v3-official-report-runbook.md).

## Cấu trúc còn dùng

```text
lab/
├── k8s/exposed/                 manifest active duy nhất
├── images/                      bốn image build của v3
├── sources/awesome-llm-apps/    source Beifong và GitHub MCP dùng để build/đối chiếu
├── sources/paperclip/           source Paperclip v0.3.1 dùng để build/đối chiếu
├── sources/security-research/   ghi chú nguồn/advisory
├── scripts/                     setup, reset, capture, redeploy, shutdown
├── evidence/campaigns/          evidence theo Campaign ID và Run ID
├── docs/                        đặc tả và hướng dẫn v3
├── _state/minikube/             trạng thái Minikube cục bộ
├── _state/kube/                 kubeconfig cục bộ
└── tools/minikube/              binary Minikube được ghim theo lab
```

## Lệnh vận hành

```powershell
cd D:\daihoc\Nam4\Doan\lab

# Chỉ chạy sau khi Docker Desktop sẵn sàng.
.\scripts\10-setup-ai-cve-lab.ps1   # lần đầu, hoặc sau khi xóa Minikube
.\scripts\90-start-ai-cve-lab.ps1   # mỗi lần làm việc
.\scripts\91-status-ai-cve-lab.ps1  # kiểm tra
.\scripts\99-stop-ai-cve-lab.ps1    # dừng
```

Các UI cục bộ: Beifong `http://127.0.0.1:19091/`, GitHub MCP adapter
`http://127.0.0.1:19501/`, Paperclip `http://127.0.0.1:19310/`, và sink
hash-only `http://127.0.0.1:19580/events`.

## An toàn và phạm vi

- Chỉ nhập chuỗi `LAB_*` giả lập; không dùng GitHub/OpenAI token thật.
- Không lưu Agent API key Paperclip thô vào ảnh, Burp export hoặc evidence.
- `evidence/campaigns/` là evidence hiện hành; mỗi lần reset toàn namespace là
  một Run ID mới.
- Một marker Paperclip chỉ ở `emptyDir` của Pod. Nó không chứng minh truy cập
  node, Docker socket hay Kubernetes API.
