[CmdletBinding()]
param(
    [string]$EvidenceRoot = "",
    [string]$CampaignId = "",
    [string]$RunId = "",
    [string]$Checkpoint = "final"
)

# Read-only GitHub MCP inventory. It records the two involved workloads,
# the selected egress policy, and hash-only events from the in-cluster sink.
$ErrorActionPreference = "Stop"
$LAB_ROOT = "D:\daihoc\Nam4\Doan\lab"
Set-Location $LAB_ROOT
. "$LAB_ROOT\scripts\00-lab-env.ps1"

if ([string]::IsNullOrWhiteSpace($CampaignId) -xor [string]::IsNullOrWhiteSpace($RunId)) {
    throw "Supply both -CampaignId and -RunId, or omit both."
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $LAB_ROOT "evidence\boundary-v3"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

function Invoke-Kubectl { & $MINIKUBE_EXE -p ai-cve-lab kubectl -- @args }

function Get-WorkloadSnapshot([string]$Selector, [string]$ContainerName, [string]$DeploymentName) {
    $pods = @(
        (Invoke-Kubectl get pods -n ai-cve-lab-exposed -l $Selector -o json | ConvertFrom-Json).items |
            Where-Object { $_.status.phase -eq "Running" -and -not $_.metadata.deletionTimestamp }
    )
    if ($pods.Count -ne 1) {
        throw "Expected exactly one running Pod selected by '$Selector'; found $($pods.Count)."
    }

    $pod = $pods[0]
    $container = @($pod.spec.containers | Where-Object { $_.name -eq $ContainerName }) | Select-Object -First 1
    $containerStatus = @($pod.status.containerStatuses | Where-Object { $_.name -eq $ContainerName }) | Select-Object -First 1
    if ($null -eq $container) {
        throw "Container '$ContainerName' was not found in Pod $($pod.metadata.name)."
    }

    [pscustomobject]@{
        deployment = $DeploymentName
        podName = $pod.metadata.name
        podUid = $pod.metadata.uid
        phase = $pod.status.phase
        node = $pod.spec.nodeName
        serviceAccount = $pod.spec.serviceAccountName
        automountServiceAccountToken = $pod.spec.automountServiceAccountToken
        container = [pscustomobject]@{
            name = $container.name
            image = $container.image
            imageId = if ($containerStatus) { $containerStatus.imageID } else { $null }
            containerId = if ($containerStatus) { $containerStatus.containerID } else { $null }
            restartCount = if ($containerStatus) { [int]$containerStatus.restartCount } else { $null }
            # A container without volumeMounts must be represented as an
            # empty JSON array, not as one null-valued mount record.
            mounts = @(
                if ($null -ne $container.volumeMounts) {
                    foreach ($mount in @($container.volumeMounts)) {
                        [pscustomobject]@{
                            name = $mount.name
                            mountPath = $mount.mountPath
                            readOnly = [bool]$mount.readOnly
                        }
                    }
                }
            )
        }
    }
}

$namespace = "ai-cve-lab-exposed"
$mcpWorkload = Get-WorkloadSnapshot -Selector "app=github-mcp-exposed" -ContainerName "github-mcp-agent" -DeploymentName "github-mcp-exposed"
$sinkWorkload = Get-WorkloadSnapshot -Selector "app=github-credential-sink" -ContainerName "credential-sink" -DeploymentName "github-credential-sink"
$policy = Invoke-Kubectl get networkpolicy github-mcp-observer-egress -n $namespace -o json | ConvertFrom-Json

# Avoid quote loss when the Python one-liner is forwarded through
# PowerShell -> minikube.exe -> kubectl on Windows.
$sinkUrl = "http://127.0.0.1:8080/events"
$sinkUrlBytes = ([System.Text.Encoding]::ASCII.GetBytes($sinkUrl) -join ",")
$sinkCode = "import urllib.request; print(urllib.request.urlopen(bytes([$sinkUrlBytes]).decode(),timeout=3).read().decode())"
$sinkOutput = @(
    & $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $namespace exec deploy/github-credential-sink -c credential-sink -- python -c $sinkCode 2>&1
)
$sinkExitCode = $LASTEXITCODE
if ($sinkExitCode -ne 0) {
    $sinkDiagnostic = ($sinkOutput | Out-String).Trim()
    throw "Unable to retrieve hash-only GitHub credential-sink events (exit $sinkExitCode): $sinkDiagnostic"
}
if (-not $sinkOutput) {
    throw "GitHub credential-sink returned no events payload."
}
try {
    $sinkEvents = (($sinkOutput | Out-String) | ConvertFrom-Json)
}
catch {
    throw "GitHub credential-sink returned invalid JSON: $($_.Exception.Message)"
}

$capture = [ordered]@{
    schemaVersion = "github-mcp-k8s-boundary-v2"
    capturedAtUtc = [DateTime]::UtcNow.ToString("o")
    campaignId = if ($CampaignId) { $CampaignId } else { $null }
    runId = if ($RunId) { $RunId } else { $null }
    checkpoint = $Checkpoint
    purpose = "GitHub MCP session/egress boundary inventory; sink records hashes and labels only"
    namespace = $namespace
    workloads = [ordered]@{
        githubMcp = $mcpWorkload
        credentialSink = $sinkWorkload
    }
    networkPolicy = [ordered]@{
        name = $policy.metadata.name
        podSelector = $policy.spec.podSelector
        policyTypes = @($policy.spec.policyTypes)
        egress = @($policy.spec.egress)
    }
    credentialSinkEvents = $sinkEvents
    interpretationLimit = "Sink events show only which synthetic credential fingerprint reached the local sink. They do not show a call to GitHub, OpenAI, or an MCP server."
}

$path = Join-Path $EvidenceRoot "github-mcp-k8s-boundary.json"
$capture | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Saved GitHub MCP Kubernetes boundary inventory: $path"
Write-Host "Hash-only sink event count: $($sinkEvents.count)"
