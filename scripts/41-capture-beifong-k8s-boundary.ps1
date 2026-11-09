[CmdletBinding()]
param(
    [string]$EvidenceRoot = "",
    [string]$CampaignId = "",
    [string]$RunId = "",
    [string]$Checkpoint = "final"
)

# Read-only, Beifong-only Kubernetes inventory. It records the runtime Pod,
# the canary volume declaration, and only a boolean filesystem-read check.
# It never reads or serializes the canary's content.
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

$namespace = "ai-cve-lab-exposed"
$pods = @(
    (Invoke-Kubectl get pods -n $namespace -l app=beifong-exposed -o json | ConvertFrom-Json).items |
        Where-Object { $_.status.phase -eq "Running" -and -not $_.metadata.deletionTimestamp }
)
if ($pods.Count -ne 1) {
    throw "Expected exactly one running Beifong Pod in $namespace; found $($pods.Count)."
}

$pod = $pods[0]
$container = @($pod.spec.containers | Where-Object { $_.name -eq "beifong" }) | Select-Object -First 1
$containerStatus = @($pod.status.containerStatuses | Where-Object { $_.name -eq "beifong" }) | Select-Object -First 1
if ($null -eq $container) {
    throw "Container 'beifong' was not found in Pod $($pod.metadata.name)."
}

$canaryPath = "/var/run/lab-canary/beifong-outside-audio.txt"
$canaryMount = @($container.volumeMounts | Where-Object { $_.mountPath -eq "/var/run/lab-canary" }) | Select-Object -First 1
if ($null -eq $canaryMount) {
    throw "Expected Beifong canary mount /var/run/lab-canary was not found."
}
$canaryVolume = @($pod.spec.volumes | Where-Object { $_.name -eq $canaryMount.name }) | Select-Object -First 1
if ($null -eq $canaryVolume) {
    throw "Volume '$($canaryMount.name)' referenced by the Beifong mount was not found."
}

# Executes only a filesystem-read test inside the evaluated container:
# a true/false check, not a read or disclosure of the mounted file.
& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $namespace exec "pod/$($pod.metadata.name)" -c beifong -- sh -lc "test -r '$canaryPath'" | Out-Null
$canaryReadable = ($LASTEXITCODE -eq 0)

$capture = [ordered]@{
    schemaVersion = "beifong-k8s-boundary-v2"
    capturedAtUtc = [DateTime]::UtcNow.ToString("o")
    campaignId = if ($CampaignId) { $CampaignId } else { $null }
    runId = if ($RunId) { $RunId } else { $null }
    checkpoint = $Checkpoint
    purpose = "Beifong Pod filesystem/volume boundary inventory; no canary contents collected"
    namespace = $namespace
    workload = [ordered]@{
        deployment = "beifong-exposed"
        podName = $pod.metadata.name
        podUid = $pod.metadata.uid
        phase = $pod.status.phase
        node = $pod.spec.nodeName
        serviceAccount = $pod.spec.serviceAccountName
        automountServiceAccountToken = $pod.spec.automountServiceAccountToken
        container = [ordered]@{
            name = $container.name
            image = $container.image
            imageId = if ($containerStatus) { $containerStatus.imageID } else { $null }
            containerId = if ($containerStatus) { $containerStatus.containerID } else { $null }
            restartCount = if ($containerStatus) { [int]$containerStatus.restartCount } else { $null }
        }
    }
    canaryVolumeBoundary = [ordered]@{
        intendedBusinessDirectory = "/app/podcasts/audio"
        mountedDirectory = $canaryMount.mountPath
        canaryPath = $canaryPath
        mountReadOnly = [bool]$canaryMount.readOnly
        volumeName = $canaryMount.name
        volumeType = if ($canaryVolume.secret) { "secret" } elseif ($canaryVolume.configMap) { "configMap" } elseif ($canaryVolume.emptyDir) { "emptyDir" } else { "other" }
        sourceName = if ($canaryVolume.secret) { $canaryVolume.secret.secretName } elseif ($canaryVolume.configMap) { $canaryVolume.configMap.name } else { $null }
        processCanReadCanary = $canaryReadable
    }
    interpretationLimit = "This establishes the filesystem scope visible to the Beifong process. It does not by itself prove an HTTP traversal response, host/node access, Kubernetes API access, or disclosure of a real secret."
}

$path = Join-Path $EvidenceRoot "beifong-k8s-boundary.json"
$capture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Saved Beifong Kubernetes boundary inventory: $path"
Write-Host "Canary readability only: Beifong=$canaryReadable"
