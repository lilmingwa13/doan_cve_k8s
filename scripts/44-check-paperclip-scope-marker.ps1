[CmdletBinding()]
param(
    # Must match the harmless filename used in the Agent API-key PoC request.
    [ValidatePattern('^[a-zA-Z0-9._-]+$')]
    [string]$MarkerName = "lab-agent-key-scope-marker",

    # Optional Run-specific directory. When present, the read-only result is
    # saved as paperclip-marker-<checkpoint>.json as well as printed.
    [string]$EvidenceRoot = "",
    [string]$CampaignId = "",
    [string]$RunId = "",
    [string]$Checkpoint = "manual"
)

# Read-only verification.  No Agent API key is required and the marker content
# is never opened; this only checks the existence of a file in the disposable
# Kubernetes emptyDir that Paperclip's execution workspace uses.
$ErrorActionPreference = "Stop"
$LAB_ROOT = "D:\daihoc\Nam4\Doan\lab"
Set-Location $LAB_ROOT
. "$LAB_ROOT\scripts\00-lab-env.ps1"

if ([string]::IsNullOrWhiteSpace($CampaignId) -xor [string]::IsNullOrWhiteSpace($RunId)) {
    throw "Supply both -CampaignId and -RunId, or omit both."
}

$path = "/workspace/repo/.paperclip/$MarkerName"
# MARKER_ABSENT is a valid baseline result, so the shell itself always exits 0.
$probe = (& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n ai-cve-lab-exposed exec deploy/paperclip-exposed -c paperclip -- sh -lc "if test -f '$path'; then printf 'MARKER_PRESENT=1'; else printf 'MARKER_PRESENT=0'; fi" | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not query the exposed Paperclip Pod." }
$present = $probe -eq "MARKER_PRESENT=1"

$identity = (& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n ai-cve-lab-exposed exec deploy/paperclip-exposed -c paperclip -- id | Out-String).Trim()
$pod = ((& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n ai-cve-lab-exposed get pods -l app=paperclip-exposed -o json | Out-String) | ConvertFrom-Json).items |
    Where-Object { $_.status.phase -eq "Running" -and -not $_.metadata.deletionTimestamp } |
    Select-Object -First 1
if ($null -eq $pod) { throw "Could not locate the running Paperclip Pod." }
$containerStatus = @($pod.status.containerStatuses | Where-Object { $_.name -eq "paperclip" }) | Select-Object -First 1
$result = [ordered]@{
    schemaVersion = "paperclip-marker-scope-v2"
    capturedAtUtc = [DateTime]::UtcNow.ToString("o")
    campaignId = if ($CampaignId) { $CampaignId } else { $null }
    runId = if ($RunId) { $RunId } else { $null }
    checkpoint = $Checkpoint
    target = "paperclip-exposed"
    podName = $pod.metadata.name
    podUid = $pod.metadata.uid
    imageId = if ($containerStatus) { $containerStatus.imageID } else { $null }
    containerId = if ($containerStatus) { $containerStatus.containerID } else { $null }
    restartCount = if ($containerStatus) { [int]$containerStatus.restartCount } else { $null }
    markerPath = $path
    markerPresent = $present
    executionIdentity = $identity
    scope = "disposable emptyDir under /workspace/repo/.paperclip; not node or cluster storage"
}

if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
    $safeCheckpoint = $Checkpoint -replace '[^A-Za-z0-9._-]', '-'
    $outputPath = Join-Path $EvidenceRoot "paperclip-marker-$safeCheckpoint.json"
    if (Test-Path -LiteralPath $outputPath) {
        throw "Marker checkpoint already exists and will not be overwritten: $outputPath"
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outputPath -Encoding utf8
    Write-Host "Saved Paperclip marker checkpoint: $outputPath"
}

[pscustomobject]$result | Format-List
