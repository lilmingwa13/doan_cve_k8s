# Đặc tả thực nghiệm cuối cùng — Chương III

## 1. Quyết định phạm vi

Chương III dùng một namespace Kubernetes duy nhất, `ai-cve-lab-exposed`, và
ba trường hợp độc lập:

| Trường hợp | Ranh giới nghiên cứu | Kết quả quan sát chính |
|---|---|---|
| Beifong | vùng file audio nghiệp vụ / file system Pod | HTTP response, canary vô hại, mount và process scope |
| GitHub MCP adapter | ownership credential giữa hai session / process state | event hash-only của sink và checkpoint process |
| Paperclip | quyền Agent API key / cấu hình dẫn tới runtime execution | PATCH, cấu hình lưu lại, run, marker workspace |

Kubernetes được dùng để xác định runtime scope: Pod nào chạy mã, image nào,
process nhìn thấy mount nào, ServiceAccount nào được gắn, và policy mạng nào
được áp dụng. Thực nghiệm không đặt mục tiêu chứng minh node access, Docker
socket access, Kubernetes API access, cluster takeover, hay chuỗi tấn công
liên ứng dụng.

Không cần bổ sung namespace hardened, CVE thứ tư, multi-node hay bản vá trước/
sau để hoàn thành phạm vi này.

## 2. Định danh và tính toàn vẹn evidence

Mỗi chiến dịch dùng một **Campaign ID**, ví dụ `CH3-20261014`; mỗi phép đo
dùng một **Run ID**, ví dụ `CH3-G3-001`. Một Run ID chỉ biểu diễn một trạng
thái namespace/POD xác định. Không ghép ảnh, JSON, request/response hoặc run
Paperclip giữa các Run ID khác nhau.

Có hai lớp baseline:

| Lớp | Phạm vi | Nội dung |
|---|---|---|
| Campaign baseline | một chiến dịch | commit nguồn, trạng thái Git, hash file liên quan, manifest, phiên bản công cụ |
| Run baseline | từng Run ID, sau reset | Pod UID, imageID, container ID, restartCount, mounts, ServiceAccount, NetworkPolicy, PID 1 của GitHub MCP |

Evidence được lưu theo cây sau:

```text
evidence/
  campaigns/
    <CAMPAIGN_ID>/
      campaign-baseline.json
      <RUN_ID>/
        runtime-baseline.json
        runtime-after-a.json              # chỉ cần cho GitHub G3
        runtime-after-b.json              # chỉ cần cho GitHub G3
        k8s/
          beifong-k8s-boundary.json
          github-mcp-k8s-boundary.json
          paperclip-marker-T0.json
          paperclip-marker-T1.json
          paperclip-marker-T2.json
        artifacts/                        # ảnh và export Burp đã che key
        run-seal.json                     # danh sách SHA-256
```

`run-seal.json` là chỉ mục integrity; nó không tự khẳng định PoC thành công.
Trước khi niêm phong, công cụ kiểm tra text evidence để chặn Bearer credential
hoặc Paperclip key thô. Agent key chỉ dùng tạm trong Burp và phải revoke sau
khi evidence đã hoàn tất.

## 3. Trình tự chung cho một Run ID

Sau khi source/image đã được khóa và redeploy nếu cần, lặp đúng trình tự này
cho **mỗi** Run ID:

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab

# 1. Tạo runtime sạch. Lệnh này thay Pod và xóa emptyDir state.
.\scripts\93-reset-active-lab.ps1

# 2. Ghi baseline của Run ID. Chỉ gọi -RequireClean ngay sau reset.
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId CH3-20261014 `
  -RunId CH3-<CASE>-001 `
  -Checkpoint baseline `
  -RequireClean
```

Không restart Pod, redeploy image hoặc gọi reset giữa các bước của cùng Run ID.
Nếu điều đó xảy ra, dừng run hiện tại và bắt đầu Run ID mới. `93-reset` chỉ
xóa direct file tại `evidence\boundary-v3`; evidence đã niêm phong nằm ở
`evidence\campaigns` và không bị reset script động tới.

Sau khi đã lưu JSON, ảnh và export request đã che credential, niêm phong run:

```powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId CH3-20261014 `
  -RunId CH3-<CASE>-001 `
  -ArtifactPath C:\duong-dan\anh-da-che-key.png,C:\duong-dan\burp-da-che-key.http
```

Không sửa artifact sau khi đã niêm phong. Nếu phải chạy lại, tạo Run ID mới;
không reseal hoặc thay nội dung của run cũ.

## 4. Khóa source/build trước chiến dịch

Sau khi chỉnh mã, rebuild đúng image trước khi bắt đầu các run mới:

```powershell
.\scripts\90-start-ai-cve-lab.ps1
.\scripts\92-redeploy-ai-cve-lab.ps1 -Images beifong-boundary-model
.\scripts\90-start-ai-cve-lab.ps1
```

`94-capture-ch3-run-state.ps1` tự tạo `campaign-baseline.json` ở lần đầu,
ghi commit của hai source checkout, trạng thái Git, hash các handler/Dockerfile
liên quan, manifest NetworkPolicy và phiên bản tool. Trong báo cáo phải nêu:

- Beifong hiện chạy handler audio với `filename:path`; nêu commit, hash
  `main.py`, Dockerfile và imageID thực tế của Run ID.
- Các thay đổi lab (seed/canary, UI/observation adapter, fixture) là gì và
  có làm thay đổi handler/sink đang nghiên cứu hay không.
- Paperclip có UI overlay phục vụ dựng dữ liệu lab; phân biệt overlay UI với
  middleware auth, route agent và workspace runtime được đối chiếu bằng hash.

Nếu một thay đổi tạo điều kiện riêng cho lab, kết luận phải gọi đúng là hành
vi của boundary model/lab build và nêu giới hạn đó. Không mô tả mô hình lab
như kết quả end-to-end của một build khác không được chạy trong chiến dịch.

## 5. Thiết kế từng trường hợp

### 5.1. Beifong — `CH3-BEIFONG-001`

1. Lấy request business path thực tế bằng thao tác **Download** trong player
   UI; dùng chính filename hiện trong HTTP history của image đang chạy.
2. Lưu request/response hợp lệ. Đây là bằng chứng chức năng audio, không phải
   bằng chứng traversal.
3. Từ request đó, tạo request canary bằng Burp Repeater hoặc
   `curl.exe --path-as-is`; chỉ thay request-target.
4. Kết quả dương tính chỉ khi body/response hash xác nhận canary vô hại.
5. Ghi Kubernetes scope vào thư mục run:

   ```powershell
   .\scripts\41-capture-beifong-k8s-boundary.ps1 `
     -CampaignId CH3-20261014 -RunId CH3-BEIFONG-001 `
     -Checkpoint final `
     -EvidenceRoot .\evidence\campaigns\CH3-20261014\CH3-BEIFONG-001\k8s
   ```

Kết luận được phép: request vượt vùng audio nghiệp vụ và đọc canary nằm trong
filesystem mà process Pod được cấp. Inventory mount chỉ chứng minh scope
runtime; HTTP response mới chứng minh file-access qua request.

### 5.2. GitHub MCP adapter — G1 đến G4

Mỗi hàng dưới đây là Run ID riêng và có reset + baseline riêng, trừ hai thao
tác A/B bên trong G3.

| Run ID mẫu | Trạng thái đầu | Thao tác | Điều kiện kết luận |
|---|---|---|---|
| `CH3-G1-001` | process sạch | A nhập credential A, Run Query | sink nhận fingerprint A, source `session input` |
| `CH3-G2-001` | process sạch | B nhập credential B, Run Query | sink nhận fingerprint B, source `session input` |
| `CH3-G3-001` | process sạch | A nhập A, sau đó B để trống GitHub token | B dùng fingerprint A qua process-global fallback |
| `CH3-G4-001` | process/sink sạch | B chạy trước, không có GitHub token | không có fingerprint A cũ; validation/no-event chỉ hợp lệ khi sink health tốt |

Trong G3, sau bước A và sau bước B, ghi hai checkpoint:

```powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId CH3-20261014 -RunId CH3-G3-001 -Checkpoint after-a

# Thao tác B diễn ra ở đây, không reset/restart.

.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId CH3-20261014 -RunId CH3-G3-001 -Checkpoint after-b
```

Pod UID, container ID, restartCount và `githubMcpPidOne.processStartTicks`
phải giữ nguyên ở baseline/after-a/after-b. `crossSessionCredentialUse=true`
không là chứng cứ duy nhất; cần đồng thời thấy B không nhập token, source là
process-global fallback, fingerprint B trùng A và sink nhận event tương ứng.

Phạm vi kết luận: credential reuse của adapter trong cùng process. Sink không
đại diện GitHub, OpenAI hay MCP server thật.

### 5.3. Paperclip — L1 và L2

Tạo hai General Agent hợp lệ cùng Company:

| Agent | Vai trò trong phép thử | Quyền cần giữ |
|---|---|---|
| A — `Ch3 Agent key scope` | target của PATCH và run | General, không `canCreateAgents` |
| B — `Ch3 General control B` | đối chứng quyền | General, không `canCreateAgents`, không grant quản lý agent khác |

Không coi Bearer không hợp lệ là đối chứng quyền chính trong `local_trusted`.
Đối chứng hai chiều dùng key hợp lệ của B:

1. B sửa cấu hình Process thông thường của **chính B**: phải thành công. Điều
   này xác nhận credential B và middleware nhận B như agent.
2. B sửa cấu hình của **A**: phải bị từ chối và GET lại cho thấy cấu hình A
   không đổi. Nếu được chấp nhận, dừng và không kết luận có ranh giới quyền.

**L1 — agent-controlled configuration → server execution** yêu cầu:

1. PATCH của key A được đối chiếu với source auth/route và kết quả đối chứng B.
2. PATCH lưu `provisionCommand`; GET lại xác nhận giá trị đã lưu.
3. Marker được đo ba lần trong cùng Pod:

   ```powershell
   .\scripts\44-check-paperclip-scope-marker.ps1 `
     -CampaignId CH3-20261014 -RunId CH3-PAPERCLIP-L1-001 `
     -Checkpoint T0 -EvidenceRoot .\evidence\campaigns\CH3-20261014\CH3-PAPERCLIP-L1-001\k8s

   # PATCH A; sau đó đo T1, trước wakeup.
   # wakeup có payload.issueId UUID; chờ run kết thúc; sau đó đo T2.
   ```

4. T0 và T1 phải là `markerPresent=false`; T2 mới được là `true`.
5. Run ID, issue UUID, log provisioning và workspace không fallback phải liên
   kết được với marker T2.

L1 vẫn hợp lệ nếu Board kích hoạt run, nhưng caption phải nói rõ Board là bên
kích hoạt. Điều được chứng minh là A kiểm soát cấu hình mà server thực thi,
không phải A tự chạy toàn bộ chuỗi.

**L2 — chuỗi chỉ bằng Agent API key** chỉ được kết luận khi PATCH và wakeup
đều có evidence auth của A, wakeup chứa Issue UUID đúng, run mới hoàn tất và
marker T2 xuất hiện. Trường `contextSnapshot` là evidence hỗ trợ; quyết định
auth phải dựa vào middleware/route đúng commit đang chạy và đối chứng B.

`run succeeded` hoặc `LAB_LOCAL_ADAPTER_COMPLETED` một mình không đủ: fixture
có thể hoàn tất dù provision command chưa chạy. Marker T0/T1/T2 và log
provisioning mới xác nhận quan hệ PATCH → wakeup/run → filesystem effect.

### 5.4. NetworkPolicy — `CH3-NETPOL-001`

Policy `github-mcp-observer-egress` chỉ chọn workload `github-mcp-exposed`.
Kết quả policy chỉ được chốt khi có đủ:

1. Runtime record cho thấy CNI đang chạy và manifest/effective policy được
   lưu trong run baseline.
2. Từ chính Pod được policy chọn, TCP/HTTP tới credential sink allow-list
   thành công.
3. Service ngoài allow-list có endpoint hoạt động độc lập.
4. Từ Pod được policy chọn, kết nối tới Service đó thất bại.
5. Từ một Pod đối chứng **không** bị selector policy chọn, kết nối cùng
   Service thành công.

Không dùng HTTP `401/403` hoặc một timeout đơn lẻ làm bằng chứng policy chặn
mạng. Nếu CNI không thực thi NetworkPolicy, ghi nhận giới hạn này; không đổi
cluster để tạo kết quả mong muốn.

## 6. Cổng chấp nhận trước khi viết kết quả

| Case | Điều kiện tối thiểu | Nếu không đạt |
|---|---|---|
| Beifong | response chứa canary và inventory xác nhận scope Pod | chỉ báo cáo request/response quan sát được, không kết luận file read |
| GitHub G3 | B blank; fallback; fingerprint A=B; sink event; process identity không đổi | không kết luận cross-session reuse |
| Paperclip L1 | A principal được đối chiếu; B self/cross control; T0/T1 false; run/log; T2 true | không gọi là privilege escalation tái hiện |
| Paperclip L2 | toàn bộ L1 và wakeup do A | chỉ báo cáo L1 nếu L1 đủ evidence |
| NetworkPolicy | allow + block + control + target/CNI validation | chỉ kết luận policy được khai báo, không kết luận cưỡng chế |

## 7. Ánh xạ vào Chương III

1. Mục tiêu, đối tượng và phạm vi.
2. Phương pháp, Campaign/Run ID và tiêu chí chấp nhận evidence.
3. Môi trường Kubernetes, source/build lock và runtime identity.
4. Beifong.
5. GitHub MCP adapter.
6. Paperclip.
7. Tổng hợp phạm vi tài nguyên/quyền/mạng Kubernetes.
8. Giới hạn và kết luận.

## 8. Trạng thái chốt evidence của Campaign `CH3-20261014`

Đây là bảng kiểm trước khi chuyển từ nhật ký lab sang nội dung báo cáo chính
thức. Nó không yêu cầu chạy lại một case đã có kết quả; nó chỉ giới hạn đúng
mức kết luận cho evidence đang giữ.

| Trường hợp | Đã có | Còn thiếu hoặc giới hạn | Cách ghi trong báo cáo chính thức |
|---|---|---|---|
| Beifong | response canary của build lab và inventory mount/Pod scope | Build lab có điều chỉnh route, do đó không đồng nhất với upstream nguyên trạng | Hành vi file read được quan sát trên build lab đã khóa; tác động giới hạn trong filesystem Pod được cấp. |
| GitHub MCP G3 | checkpoint `after-a`/`after-b` và sink event cho A/B | Cây evidence hiện chưa có `runtime-baseline.json` cho chính `CH3-G3-001`; G1/G2/G4 chưa là bộ đối chứng đầy đủ | Reuse được quan sát trong adapter process của G3; không mở rộng sang dịch vụ thật hoặc toàn bộ tình huống G1–G4. Muốn baseline sạch phải chạy Run ID mới. |
| Paperclip | B self/cross control, PATCH, marker T0/T1/T2 | Chưa có final status/events/log provisioning của run được liên kết với T2 trong cây evidence | Có quan sát cấu hình do Agent điều khiển và marker workspace; chưa chốt toàn bộ chuỗi end-to-end cho đến khi có final run/log. |
| NetworkPolicy | allow sink, target/control sống; selected GitHub Pod vẫn tới Beifong ngoài allow-list | `observedPatternMatchesPolicy = false` | Policy được khai báo, nhưng phép đo runtime chưa xác nhận enforcement egress; không suy diễn cơ chế packet-drop. |
| Integrity | Campaign/Run directory có JSON hiện hữu | Chưa có `run-seal.json` cho các Run đang giữ | Chỉ đưa artifact đã che credential và có `run-seal.json` vào phụ lục chính thức. |

Không tạo `runtime-baseline.json` muộn cho một Run đã có after-checkpoint;
điều đó không chứng minh trạng thái đầu. Khi cần hoàn thiện G3/Paperclip, dùng
một Run ID mới: reset → baseline `-RequireClean` → thao tác case → capture →
che credential → seal. Nếu không chạy bổ sung, giữ nguyên các giới hạn trong
cột cuối thay vì suy diễn thêm.

Mỗi mục case sử dụng cùng khuôn: điều kiện đầu → business control → thao tác
kiểm thử → runtime evidence → Kubernetes scope → kết luận/giới hạn. Chỉ dùng
artifact cùng Run ID trong một chuỗi kết luận.
