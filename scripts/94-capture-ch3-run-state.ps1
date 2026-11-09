[CmdletBinding()]
param(
    # One umbrella experiment campaign, for example CH3-20261014.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$CampaignId,

    # One reproducible scenario on one deployment state, for example CH3-G3-001.
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$RunId,

    # Use baseline after reset.  GitHub G3 additionally records after-a and after-b.
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{1,79}$')]
    [string]$Checkpoint = 'baseline',

    # Valid only immediately after 93-reset-active-lab.ps1.  It verifies the
    # three clean-state properties before writing a new baseline.
    [switch]$RequireClean
)

# Read-only Chapter III runtime capture.  It creates a campaign source/build
# lock once, then writes one immutable checkpoint per Run ID.  It never resets
# Pods, changes application data, reads Secret values, or displays API keys.
$ErrorActionPreference = 'Stop'
$LAB_ROOT = 'D:\daihoc\Nam4\Doan\lab'
$NAMESPACE = 'ai-cve-lab-exposed'
$CAMPAIGN_ROOT = Join-Path $LAB_ROOT "evidence\campaigns\$CampaignId"
$RUN_ROOT = Join-Path $CAMPAIGN_ROOT $RunId

Set-Location $LAB_ROOT
. "$LAB_ROOT\scripts\00-lab-env.ps1"

function Invoke-LabKubectl {
    # Do not use ValueFromRemainingArguments here.  PowerShell otherwise tries
    # to bind kubectl's `-o` to its own -OutVariable/-OutBuffer common params.
    param([Parameter(Mandatory = $true)][string[]]$KubectlArgs)
    $output = & $MINIKUBE_EXE -p ai-cve-lab kubectl -- @KubectlArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl failed: $($KubectlArgs -join ' '): $(($output | Out-String).Trim())"
    }
    return @($output)
}

function Get-KubectlJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $text = (Invoke-LabKubectl -KubectlArgs $Arguments | Out-String)
    try { return ($text | ConvertFrom-Json) }
    catch { throw "kubectl did not return valid JSON for '$($Arguments -join ' ')': $($_.Exception.Message)" }
}

function Get-GitSourceLock {
    param([Parameter(Mandatory = $true)][string]$Path)
    $head = (& git -C $Path rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) {
        throw "Expected a Git source checkout at $Path."
    }
    $status = @(& git -C $Path status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not read Git status for $Path." }
    return [ordered]@{ path = $Path; commit = $head; statusPorcelain = $status }
}

function Get-FileLock {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $LAB_ROOT $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required source/build file is missing: $RelativePath"
    }
    return [ordered]@{
        path = $RelativePath
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-PodProjection {
    param([Parameter(Mandatory = $true)]$Pod)
    $statuses = @($Pod.status.containerStatuses)
    $containers = @(
        foreach ($container in @($Pod.spec.containers)) {
            $status = @($statuses | Where-Object { $_.name -eq $container.name }) | Select-Object -First 1
            [ordered]@{
                name = $container.name
                image = $container.image
                imageId = if ($status) { $status.imageID } else { $null }
                containerId = if ($status) { $status.containerID } else { $null }
                restartCount = if ($status) { [int]$status.restartCount } else { $null }
                startedAt = if ($status -and $status.state.running) { $status.state.running.startedAt } else { $null }
                mounts = @(
                    foreach ($mount in @($container.volumeMounts)) {
                        [ordered]@{ name = $mount.name; mountPath = $mount.mountPath; readOnly = [bool]$mount.readOnly }
                    }
                )
            }
        }
    )
    return [ordered]@{
        name = $Pod.metadata.name
        uid = $Pod.metadata.uid
        phase = $Pod.status.phase
        node = $Pod.spec.nodeName
        serviceAccount = $Pod.spec.serviceAccountName
        automountServiceAccountToken = $Pod.spec.automountServiceAccountToken
        createdAt = $Pod.metadata.creationTimestamp
        containers = $containers
    }
}

function Get-GithubPidOneProjection {
    param([Parameter(Mandatory = $true)][string]$PodName)
    # PID 1 is the Streamlit/Python process for this adapter image.  Start ticks
    # come from /proc and are compared before/after G3 without exposing env vars.
    $probe = @(& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $NAMESPACE exec "pod/$PodName" -c github-mcp-agent -- sh -lc "cat /proc/1/stat; printf '\n__CMDLINE__\n'; tr '\000' ' ' < /proc/1/cmdline" 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not read process identity from GitHub MCP Pod ${PodName}: $(($probe | Out-String).Trim())"
    }
    $marker = [Array]::IndexOf($probe, '__CMDLINE__')
    if ($marker -lt 1) { throw 'GitHub MCP process probe returned an unexpected format.' }
    $stat = [string]$probe[0]
    $fields = $stat -split '\s+'
    return [ordered]@{
        pid = 1
        processStartTicks = if ($fields.Count -gt 21) { $fields[21] } else { $null }
        commandLine = (($probe | Select-Object -Skip ($marker + 1)) -join ' ').Trim()
    }
}

function Get-CleanState {
    $sink = Invoke-RestMethod -Uri 'http://127.0.0.1:19580/events' -Method Get -ErrorAction Stop
    $companiesRaw = Invoke-RestMethod -Uri 'http://127.0.0.1:19310/api/companies' -Method Get -ErrorAction Stop
    $companies = @($companiesRaw | Where-Object { $null -ne $_ })
    $marker = (& $MINIKUBE_EXE -p ai-cve-lab kubectl -- -n $NAMESPACE exec deploy/paperclip-exposed -c paperclip -- sh -lc "if test -e '/workspace/repo/.paperclip/lab-agent-key-scope-marker'; then printf MARKER_EXISTS; else printf MARKER_ABSENT; fi" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Paperclip marker state.' }
    return [ordered]@{
        credentialSinkEventCount = [int]$sink.count
        paperclipCompanyCount = $companies.Count
        paperclipMarker = $marker
    }
}

New-Item -ItemType Directory -Force -Path $RUN_ROOT | Out-Null
$checkpointPath = Join-Path $RUN_ROOT "runtime-$Checkpoint.json"
if (Test-Path -LiteralPath $checkpointPath) {
    throw "Checkpoint already exists and will not be overwritten: $checkpointPath"
}

$campaignBaselinePath = Join-Path $CAMPAIGN_ROOT 'campaign-baseline.json'
if (-not (Test-Path -LiteralPath $campaignBaselinePath)) {
    $campaignBaseline = [ordered]@{
        schemaVersion = 'chapter3-campaign-baseline-v1'
        campaignId = $CampaignId
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        purpose = 'Static source/build and environment provenance for a Chapter III campaign; no Secret or API-key values recorded.'
        sourceRepositories = @(
            (Get-GitSourceLock -Path (Join-Path $LAB_ROOT 'sources\awesome-llm-apps')),
            (Get-GitSourceLock -Path (Join-Path $LAB_ROOT 'sources\paperclip'))
        )
        relevantFileHashes = @(
            (Get-FileLock 'sources\awesome-llm-apps\advanced_ai_agents\multi_agent_apps\ai_news_and_podcast_agents\beifong\main.py'),
            (Get-FileLock 'images\beifong-boundary-model\Dockerfile'),
            (Get-FileLock 'images\github-mcp-lab-adapter\github_agent.py'),
            (Get-FileLock 'images\github-mcp-lab-adapter\Dockerfile'),
            (Get-FileLock 'images\paperclip\Dockerfile'),
            (Get-FileLock 'sources\paperclip\server\src\middleware\auth.ts'),
            (Get-FileLock 'sources\paperclip\server\src\routes\agents.ts'),
            (Get-FileLock 'sources\paperclip\server\src\services\workspace-runtime.ts'),
            (Get-FileLock 'k8s\exposed\02-networkpolicy.yaml')
        )
        tooling = [ordered]@{
            minikubeVersion = (& $MINIKUBE_EXE version | Out-String).Trim()
            kubernetesVersion = ((Invoke-LabKubectl -KubectlArgs @('version', '-o', 'json') | Out-String) | ConvertFrom-Json)
            dockerVersion = (& docker version --format '{{json .Server.Version}}' 2>$null | Out-String).Trim()
        }
    }
    $campaignBaseline | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $campaignBaselinePath -Encoding utf8
    Write-Host "Created campaign baseline: $campaignBaselinePath"
}

$podsRaw = Get-KubectlJson -Arguments @('get', 'pods', '-n', $NAMESPACE, '-o', 'json')
$podProjections = @($podsRaw.items | Where-Object { -not $_.metadata.deletionTimestamp } | ForEach-Object { Get-PodProjection -Pod $_ })
$githubPod = @($podProjections | Where-Object { $_.name -like 'github-mcp-exposed-*' }) | Select-Object -First 1
if (-not $githubPod) { throw 'Could not find the running github-mcp-exposed Pod.' }

$cleanState = $null
if ($RequireClean) {
    $cleanState = Get-CleanState
    if ($cleanState.credentialSinkEventCount -ne 0 -or $cleanState.paperclipCompanyCount -ne 0 -or $cleanState.paperclipMarker -ne 'MARKER_ABSENT') {
        throw "Run baseline is not clean: sink=$($cleanState.credentialSinkEventCount), companies=$($cleanState.paperclipCompanyCount), marker=$($cleanState.paperclipMarker). Run 93-reset-active-lab.ps1 and retry."
    }
}

$networkPolicies = Get-KubectlJson -Arguments @('get', 'networkpolicy', '-n', $NAMESPACE, '-o', 'json')
$kubeSystemPods = Get-KubectlJson -Arguments @('get', 'pods', '-n', 'kube-system', '-o', 'json')
$capture = [ordered]@{
    schemaVersion = 'chapter3-run-state-v1'
    campaignId = $CampaignId
    runId = $RunId
    checkpoint = $Checkpoint
    capturedAtUtc = [DateTime]::UtcNow.ToString('o')
    namespace = $NAMESPACE
    purpose = 'Per-run runtime baseline/checkpoint. It does not read Secret values, environment values, or API keys.'
    cleanState = $cleanState
    pods = $podProjections
    githubMcpPidOne = Get-GithubPidOneProjection -PodName $githubPod.name
    networkPolicies = @($networkPolicies.items | ForEach-Object {
        [ordered]@{ name = $_.metadata.name; podSelector = $_.spec.podSelector; policyTypes = @($_.spec.policyTypes); egress = @($_.spec.egress) }
    })
    kubeSystemPodImages = @($kubeSystemPods.items | ForEach-Object {
        [ordered]@{ name = $_.metadata.name; namespace = $_.metadata.namespace; images = @($_.spec.containers | ForEach-Object { $_.image }) }
    })
    campaignBaseline = $campaignBaselinePath
}

$capture | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $checkpointPath -Encoding utf8
Write-Host "Saved Chapter III runtime checkpoint: $checkpointPath"
Write-Host "Campaign=$CampaignId Run=$RunId Checkpoint=$Checkpoint GitHubPid1StartTicks=$($capture.githubMcpPidOne.processStartTicks)"
