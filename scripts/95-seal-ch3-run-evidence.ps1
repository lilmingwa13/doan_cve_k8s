[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$CampaignId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,79}$')]
    [string]$RunId,

    # Sanitized screenshots, Burp exports, or terminal captures to include.
    # Agent API keys must be redacted before they are supplied here.
    [string[]]$ArtifactPath = @()
)

# Copies explicitly named, already-sanitized artifacts into a Run folder and
# creates a SHA-256 manifest.  It never deletes source artifacts or overwrites
# a seal.  It fails closed if a likely raw Paperclip key/Bearer value appears in
# text evidence.
$ErrorActionPreference = 'Stop'
$LAB_ROOT = 'D:\daihoc\Nam4\Doan\lab'
$RUN_ROOT = Join-Path $LAB_ROOT "evidence\campaigns\$CampaignId\$RunId"
$SEAL_PATH = Join-Path $RUN_ROOT 'run-seal.json'

if (-not (Test-Path -LiteralPath $RUN_ROOT -PathType Container)) {
    throw "Run folder does not exist. Capture a baseline first: $RUN_ROOT"
}
if (Test-Path -LiteralPath $SEAL_PATH) {
    throw "Run evidence is already sealed and will not be overwritten: $SEAL_PATH"
}

$artifactRoot = Join-Path $RUN_ROOT 'artifacts'
foreach ($source in $ArtifactPath) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Artifact is not a readable file: $source"
    }
    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    $target = Join-Path $artifactRoot ([IO.Path]::GetFileName($source))
    if (Test-Path -LiteralPath $target) {
        throw "Artifact name already exists in this run; rename it before sealing: $target"
    }
    Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
}

$textExtensions = @('.txt', '.json', '.md', '.http', '.log', '.xml', '.html', '.csv')
$textFiles = @(Get-ChildItem -LiteralPath $RUN_ROOT -Recurse -File | Where-Object { $textExtensions -contains $_.Extension.ToLowerInvariant() })
$bearerPattern = '(?im)^\s*authorization\s*:\s*bearer\s+(?!<[^>]+>|redacted\b)[^\s]+'
$paperclipKeyPattern = '\bpcp_[A-Za-z0-9_-]{8,}\b'
foreach ($file in $textFiles) {
    $matches = Select-String -LiteralPath $file.FullName -Pattern @($bearerPattern, $paperclipKeyPattern) -AllMatches -ErrorAction Stop
    if ($matches) {
        throw "Possible raw credential detected in $($file.FullName). Redact it, then run sealing again."
    }
}

$files = @(
    Get-ChildItem -LiteralPath $RUN_ROOT -Recurse -File |
        Where-Object { $_.FullName -ne $SEAL_PATH } |
        Sort-Object FullName |
        ForEach-Object {
            [ordered]@{
                relativePath = $_.FullName.Substring($RUN_ROOT.Length).TrimStart('\')
                bytes = $_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
)

if ($files.Count -eq 0) {
    throw 'No runtime checkpoint or evidence files were found to seal.'
}

$seal = [ordered]@{
    schemaVersion = 'chapter3-run-seal-v1'
    campaignId = $CampaignId
    runId = $RunId
    sealedAtUtc = [DateTime]::UtcNow.ToString('o')
    purpose = 'Integrity index for one Chapter III run. Hashes identify files; this seal does not assert that a result is positive.'
    files = $files
}
$seal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SEAL_PATH -Encoding utf8
Write-Host "Sealed $($files.Count) artifact(s): $SEAL_PATH"
