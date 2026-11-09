[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$CampaignId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceRoot
)

# Controlled NetworkPolicy measurement.  It sends only GET requests to two
# in-cluster lab services.  A failed connection is recorded as an observation,
# not automatically labeled as policy enforcement.
$ErrorActionPreference = 'Stop'
$LAB_ROOT = 'D:\daihoc\Nam4\Doan\lab'
$NAMESPACE = 'ai-cve-lab-exposed'
Set-Location $LAB_ROOT
. "$LAB_ROOT\scripts\00-lab-env.ps1"
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null

function Invoke-ExecJson {
    param(
        [Parameter(Mandatory = $true)][string]$Deployment,
        [Parameter(Mandatory = $true)][string]$Container,
        [Parameter(Mandatory = $true)][string]$Url
    )
    $python = @"
import json, urllib.request
url = $(ConvertTo-Json -Compress $Url)
try:
    response = urllib.request.urlopen(url, timeout=4)
    print(json.dumps({"ok": True, "status": response.status}))
except Exception as exc:
    print(json.dumps({"ok": False, "errorType": type(exc).__name__, "error": str(exc)[:200]}))
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($python))
    $runner = "import base64;exec(base64.b64decode('$encoded'))"
    $output = @(& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $NAMESPACE exec "deploy/$Deployment" -c $Container -- python -c $runner 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not execute network probe in $Deployment/${Container}: $(($output | Out-String).Trim())"
    }
    try { return (($output | Out-String) | ConvertFrom-Json) }
    catch { throw "Network probe returned invalid JSON: $(($output | Out-String).Trim())" }
}

$beifongEndpoints = ((& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $NAMESPACE get endpointslice -l 'kubernetes.io/service-name=beifong-exposed' -o json | Out-String) | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not read Beifong EndpointSlices.' }
$policy = ((& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $NAMESPACE get networkpolicy github-mcp-observer-egress -o json | Out-String) | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not read github-mcp-observer-egress.' }
$cniPods = ((& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n kube-system get pods -o json | Out-String) | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not read kube-system Pods.' }

$allowSink = Invoke-ExecJson -Deployment 'github-mcp-exposed' -Container 'github-mcp-agent' -Url 'http://github-credential-sink:8080/events'
$blockBeifong = Invoke-ExecJson -Deployment 'github-mcp-exposed' -Container 'github-mcp-agent' -Url 'http://beifong-exposed:80/'
$controlBeifong = Invoke-ExecJson -Deployment 'beifong-exposed' -Container 'beifong' -Url 'http://beifong-exposed:80/'

$matchesExpected = [bool]($allowSink.ok -and -not $blockBeifong.ok -and $controlBeifong.ok)
$capture = [ordered]@{
    schemaVersion = 'github-mcp-networkpolicy-measurement-v1'
    campaignId = $CampaignId
    runId = $RunId
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'Allow/block/control measurement from selected application Pods; GET only, no external destinations or credentials.'
    policy = [ordered]@{ name = $policy.metadata.name; podSelector = $policy.spec.podSelector; policyTypes = @($policy.spec.policyTypes); egress = @($policy.spec.egress) }
    targetHealth = [ordered]@{ service = 'beifong-exposed'; endpointSliceCount = @($beifongEndpoints.items).Count; endpointReady = @($beifongEndpoints.items | ForEach-Object { $_.endpoints } | ForEach-Object { $_ } | Where-Object { $_.conditions.ready -ne $false }).Count }
    probes = [ordered]@{
        allowSinkFromSelectedGithubPod = $allowSink
        blockBeifongFromSelectedGithubPod = $blockBeifong
        controlBeifongFromUnselectedBeifongPod = $controlBeifong
    }
    kubeSystemPodImages = @($cniPods.items | ForEach-Object { [ordered]@{ name = $_.metadata.name; images = @($_.spec.containers | ForEach-Object { $_.image }) } })
    observedPatternMatchesPolicy = $matchesExpected
    interpretationLimit = 'A failed selected-Pod connection supports enforcement only together with the live target, unselected-Pod control, policy selector, and CNI/runtime evidence. This JSON does not prove the exact packet-drop mechanism by itself.'
}

$path = Join-Path $EvidenceRoot 'github-mcp-networkpolicy-measurement.json'
if (Test-Path -LiteralPath $path) { throw "NetworkPolicy evidence already exists and will not be overwritten: $path" }
$capture | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Saved NetworkPolicy measurement: $path"
Write-Host "Expected allow/block/control pattern: $matchesExpected"
