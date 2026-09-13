param(
    [Parameter(Mandatory = $true)][string]$ToolchainRoot,
    [Parameter(Mandatory = $true)][string]$DeviceId
)
$ErrorActionPreference = 'Stop'
$flutter = Join-Path $ToolchainRoot 'flutter\bin\flutter.bat'
if (!(Test-Path -LiteralPath $flutter)) { throw 'Flutter was not found in the toolchain directory' }
$env:JAVA_HOME = Join-Path $ToolchainRoot 'jdk-17'
$env:ANDROID_SDK_ROOT = Join-Path $ToolchainRoot 'android-sdk'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    Write-Output 'Open the installed Hermes Personal Dev app on the connected phone.'
    Write-Output 'Press r to hot reload Dart edits, R to restart the Dart app, or d to detach.'
    & $flutter attach -d $DeviceId --app-id com.tarkilhk.hermes.android -t lib/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'Could not attach to the Personal development app' }
} finally {
    Pop-Location
}
