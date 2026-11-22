# PowerShell wrapper for scripts/release-curseforge.mjs
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThruArgs
)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
node (Join-Path $scriptDir "release-curseforge.mjs") @PassThruArgs
exit $LASTEXITCODE
