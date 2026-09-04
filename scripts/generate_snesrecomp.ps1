param(
    [Parameter(Mandatory = $true)]
    [string]$Rom,

    [string]$Python = "python",

    [string]$SnesrecompRoot = "",

    [ValidateSet("native", "python", "auto")]
    [string]$AnalysisBackend = "native",

    [int]$MaxInstructions = 4096,

    [int]$MaxNodes = 100000,

    [int]$BankShardThresholdKiB = 1024,

    [int]$BankShardPcSpan = 0x10
)

$ErrorActionPreference = "Stop"

$Repository = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($SnesrecompRoot)) {
    $SnesrecompRoot = Join-Path $Repository "snesrecomp"
} else {
    $SnesrecompRoot = (Resolve-Path -LiteralPath $SnesrecompRoot).Path
}
$OutputDirectory = Join-Path $Repository "generated\snesrecomp"
$Generator = Join-Path $PSScriptRoot "generate_snesrecomp.py"
$GeneratorArguments = @(
    $Generator,
    "--rom", $Rom,
    "--snesrecomp-root", $SnesrecompRoot,
    "--analysis-backend", $AnalysisBackend,
    "--max-instructions", "$MaxInstructions",
    "--max-nodes", "$MaxNodes",
    "--bank-shard-threshold-kib", "$BankShardThresholdKiB",
    "--bank-shard-pc-span", "$BankShardPcSpan"
)

& $Python @GeneratorArguments
if ($LASTEXITCODE -ne 0) {
    throw "snesrecomp generation failed with exit code $LASTEXITCODE."
}

# The emitter may replace its output directory atomically. On Windows, a
# directory created by a restricted build account can retain a protected ACL
# after that move, preventing the interactive owner from reading ignored build
# artifacts. Re-enable normal parent inheritance on the complete generated
# tree without changing its contents.
if ($env:OS -eq "Windows_NT") {
    & icacls.exe $OutputDirectory /inheritance:e /T /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Could not restore inherited permissions on $OutputDirectory."
    }
}

Write-Host "Generated private sources in $OutputDirectory"
Write-Host "The ROM and generated game code remain ignored by Git."
