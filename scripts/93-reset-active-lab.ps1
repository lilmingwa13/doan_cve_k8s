[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    # Rebuild and load local images before recreating the active namespace.
    # Omit this switch for an ordinary clean-state reset: the images already
    # used by the working lab are retained and only runtime state is recreated.
    [switch]$RebuildImages,

    # Retain generated JSON/screenshots under evidence\boundary-v3. The default
    # is a clean evidence directory so a new capture cannot be confused with a
    # previous run.
    [switch]$KeepEvidence
)

# ============================================================================
# Reset the ACTIVE v3 experiment only.
#
# This script recreates namespace ai-cve-lab-exposed through the canonical
# setup script. That removes all three applications' disposable runtime state:
# - Beifong: fresh Pod and synthetic mount canary;
# - GitHub MCP: process-global values and sink /tmp events are gone;
# - Paperclip: Company, Project, Agent, Issue, Run, Agent API key, worktree,
#   and marker are gone because their volumes are emptyDir.
#
# It never deletes sources, images, manifests, historical evidence outside
# evidence\boundary-v3, Minikube itself, or another Paperclip instance such as
# http://127.0.0.1:3100.
# ============================================================================

$ErrorActionPreference = "Stop"
$LAB_ROOT = "D:\daihoc\Nam4\Doan\lab"
$ACTIVE_NAMESPACE = "ai-cve-lab-exposed"
$EVIDENCE_ROOT = Join-Path $LAB_ROOT "evidence\boundary-v3"
$MARKER_PATH = "/workspace/repo/.paperclip/lab-agent-key-scope-marker"

function Assert-ExpectedLabRoot {
    $expected = [System.IO.Path]::GetFullPath("D:\daihoc\Nam4\Doan\lab").TrimEnd('\')
    $actual = (Resolve-Path -LiteralPath $LAB_ROOT -ErrorAction Stop).Path.TrimEnd('\')
    if ($actual -ne $expected) {
        throw "Safety check failed: LAB_ROOT must be exactly $expected; received $actual."
    }
}

function Invoke-LabKubectl {
    & $MINIKUBE_EXE -p ai-cve-lab kubectl -- @args
    if ($LASTEXITCODE -ne 0) { throw "kubectl failed: $($args -join ' ')" }
}

function Ensure-MinikubeProfile {
    $dockerContext = ((& docker context show 2>$null) | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Cannot read Docker context. Open Docker Desktop and retry." }
    if ($dockerContext -ne "desktop-linux") {
        docker context use desktop-linux | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Docker context desktop-linux is unavailable. Open Docker Desktop and retry." }
    }

    & $MINIKUBE_EXE -p ai-cve-lab start --driver=docker
    if ($LASTEXITCODE -ne 0) { throw "Minikube profile ai-cve-lab did not start." }
    & $MINIKUBE_EXE -p ai-cve-lab update-context
    if ($LASTEXITCODE -ne 0) { throw "Could not restore the ai-cve-lab Kubernetes context." }
    Invoke-LabKubectl get nodes -o wide
}

function Remove-CurrentEvidence {
    if ($KeepEvidence) {
        Write-Host "Keeping generated evidence because -KeepEvidence was supplied."
        return @()
    }

    if (-not (Test-Path -LiteralPath $EVIDENCE_ROOT)) {
        New-Item -ItemType Directory -Path $EVIDENCE_ROOT -Force | Out-Null
        return @()
    }

    $resolvedEvidence = (Resolve-Path -LiteralPath $EVIDENCE_ROOT -ErrorAction Stop).Path.TrimEnd('\')
    $resolvedLab = (Resolve-Path -LiteralPath $LAB_ROOT -ErrorAction Stop).Path.TrimEnd('\')
    $labPrefix = "$resolvedLab\"
    if (-not $resolvedEvidence.StartsWith($labPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Safety check failed: evidence directory is outside LAB_ROOT: $resolvedEvidence"
    }

    # boundary-v3 is reserved for generated runtime evidence. Delete direct
    # files only: no recursive delete, no historical evidence, no source files.
    $files = @(Get-ChildItem -LiteralPath $resolvedEvidence -Force -File -ErrorAction Stop)
    $removed = @()
    foreach ($file in $files) {
        if ($PSCmdlet.ShouldProcess($file.FullName, "Remove generated active-lab evidence")) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
            $removed += $file.Name
        }
    }
    return $removed
}

function Wait-PaperclipApiReady {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 120,
        [int]$RetryDelaySeconds = 2
    )

    # `kubectl rollout status` only confirms that the paperclip and proxy
    # containers are ready.  Paperclip then starts its embedded PostgreSQL,
    # applies migrations, and starts the Node server behind Nginx.  During that
    # short interval Nginx can accept a connection on 19310 but return 502.
    $healthUri = "http://127.0.0.1:19310/api/health"
    $companiesUri = "http://127.0.0.1:19310/api/companies"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastFailure = "No request has been made yet."

    Write-Host "Waiting for the Paperclip API to finish starting..."
    while ((Get-Date) -lt $deadline) {
        try {
            $health = Invoke-RestMethod -Uri $healthUri -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($health.status -ne "ok") {
                throw "Paperclip health reported status '$($health.status)'."
            }

            # A successful companies request verifies the Nginx-to-Node path
            # used by the clean-state check, not merely the proxy listener.
            $companyResult = Invoke-RestMethod -Uri $companiesUri -Method Get -TimeoutSec 5 -ErrorAction Stop
            Write-Host "Paperclip API is ready."
            return @($companyResult | Where-Object { $null -ne $_ })
        } catch {
            $lastFailure = $_.Exception.Message
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    throw "Paperclip API did not become ready within $TimeoutSeconds seconds. Last failure: $lastFailure"
}

Assert-ExpectedLabRoot
Set-Location $LAB_ROOT
. "$LAB_ROOT\scripts\00-lab-env.ps1"

if (-not $PSCmdlet.ShouldProcess(
        "namespace $ACTIVE_NAMESPACE and evidence\\boundary-v3",
        "Recreate active lab and remove generated evidence")) {
    return
}

Write-Host "=== Reset active AI CVE Lab v3 ==="
Write-Host "Scope: $ACTIVE_NAMESPACE only; Paperclip port 3100 and non-v3 evidence are untouched."

# A normal reset deliberately does not reload images. Reloading all images on
# every clean capture is slow and can hang while Docker Desktop is recovering;
# the running lab already has the exact tags declared by k8s\exposed. Use the
# explicit switch only after an image/source edit.
if ($RebuildImages) {
    & "$LAB_ROOT\scripts\10-setup-ai-cve-lab.ps1"
    if ($LASTEXITCODE -ne 0) { throw "The active namespace was not recreated successfully." }
} else {
    Ensure-MinikubeProfile
    Write-Host "`n=== Recreate active namespace only ==="
    Invoke-LabKubectl delete namespace $ACTIVE_NAMESPACE --ignore-not-found --wait=true
    Invoke-LabKubectl apply -f "$LAB_ROOT\k8s\exposed"
}

foreach ($deployment in @(
    "beifong-exposed",
    "github-mcp-exposed",
    "github-credential-sink",
    "paperclip-exposed"
)) {
    Invoke-LabKubectl rollout status "deployment/$deployment" -n $ACTIVE_NAMESPACE --timeout=240s
}

# Re-establish managed loopback port-forwards and the local Paperclip completion
# fixture.  The start script owns only pf-ai-cve-* processes.
& "$LAB_ROOT\scripts\90-start-ai-cve-lab.ps1"
if ($LASTEXITCODE -ne 0) { throw "The active namespace is ready, but managed port-forwards could not be started." }

$removedEvidence = Remove-CurrentEvidence

Write-Host "`n=== Verify clean runtime state ==="
$deployments = @(
    "beifong-exposed",
    "github-mcp-exposed",
    "github-credential-sink",
    "paperclip-exposed"
)
foreach ($deployment in $deployments) {
    Invoke-LabKubectl rollout status "deployment/$deployment" -n $ACTIVE_NAMESPACE --timeout=180s
}

$markerProbe = (& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $ACTIVE_NAMESPACE exec deploy/paperclip-exposed -c paperclip -- sh -lc "if test -e '$MARKER_PATH'; then printf MARKER_EXISTS; else printf MARKER_ABSENT; fi" | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not verify Paperclip marker state." }

$sink = Invoke-RestMethod -Uri "http://127.0.0.1:19580/events" -Method Get -ErrorAction Stop
$sinkCount = [int]$sink.count
$companies = Wait-PaperclipApiReady

[pscustomobject]@{
    namespace = $ACTIVE_NAMESPACE
    beifong = "fresh Pod; only synthetic canary mount remains"
    githubMcp = "fresh process; no prior session/process-global state"
    credentialSinkEventCount = $sinkCount
    paperclipCompanyCount = $companies.Count
    paperclipMarker = $markerProbe
    removedEvidenceFiles = if ($KeepEvidence) { "kept by -KeepEvidence" } elseif ($removedEvidence.Count -eq 0) { "none" } else { $removedEvidence -join ", " }
    untouched = "sources, images, manifests, non-v3 evidence, Minikube profile, and Paperclip on port 3100"
} | Format-List

if ($sinkCount -ne 0 -or $companies.Count -ne 0 -or $markerProbe -ne "MARKER_ABSENT") {
    throw "Reset verification failed: active v3 runtime is not empty. Do not start a new capture."
}

Write-Host "`nReset complete. Open only http://127.0.0.1:19310/ and press Ctrl+F5."
Write-Host "The correct first screen is the Company / Agent / Task / Launch wizard."
Write-Host "Then follow docs\lab-v3-boundary-scenarios.md from Paperclip section 3."
