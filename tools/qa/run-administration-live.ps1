param(
    [string]$HermesSource = "$env:LOCALAPPDATA/hermes/hermes-agent",
    [string]$ToolchainRoot = 'C:/Users/rober/Development/android-dev',
    [string]$Device = 'emulator-5556',
    [string]$Name,
    [switch]$KeepBackend
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$python = Join-Path $HermesSource 'venv/Scripts/python.exe'
$adb = Join-Path $ToolchainRoot 'android-sdk/platform-tools/adb.exe'
if (!(Test-Path -LiteralPath $python)) { throw "Hermes Python not found: $python" }
if (!$Device.StartsWith('emulator-')) { throw 'Use a disposable emulator for this suite.' }
$probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$probe.Start()
$port = $probe.LocalEndpoint.Port
$probe.Stop()
$run = 'admin-live-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$qaHome = Join-Path ([IO.Path]::GetTempPath()) $run
$evidence = Join-Path $repo "build/$run"
New-Item -ItemType Directory -Path $qaHome,$evidence | Out-Null
Set-Content -LiteralPath (Join-Path $qaHome 'config.yaml') -Value @'
model:
  provider: openrouter
  default: openai/gpt-4o-mini
'@
$previousHome = $env:HERMES_HOME
$env:HERMES_HOME = $qaHome
$env:JAVA_HOME = Join-Path $ToolchainRoot 'jdk-17'
$env:ANDROID_SDK_ROOT = Join-Path $ToolchainRoot 'android-sdk'
$backend = $null
$result = 1
try {
    $backend = Start-Process -FilePath $python -ArgumentList @('-m','hermes_cli.main','serve','--host','127.0.0.1','--port',"$port") -WorkingDirectory $HermesSource -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $evidence 'backend.out.log') -RedirectStandardError (Join-Path $evidence 'backend.err.log')
    Write-Output "QA backend PID=$($backend.Id) PORT=$port HOME=$qaHome"
    Write-Output "Evidence: $evidence"
    & $python (Join-Path $repo 'tools/qa/prepare_administration_live.py') --home $qaHome --port $port
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare disposable QA data' }
    & $adb -s $Device reverse "tcp:$port" "tcp:$port"
    $arguments = @('test','--no-pub','integration_test/administration_live_test.dart','-d',$Device,"--dart-define=HERMES_TEST_PORT=$port",'--dart-define=HERMES_ADMIN_DISPOSABLE=true',"--dart-define=HERMES_QA_PYTHON=$python","--dart-define=HERMES_QA_MCP=$repo/integration_test/fixtures/administration_mcp.py",'--reporter=expanded')
    if ($Name) { $arguments += @('--name',$Name) }
    Push-Location $repo
    try {
        & (Join-Path $repo 'scripts/invoke-flutter.ps1') -ToolchainRoot $ToolchainRoot -FlutterArguments $arguments *> (Join-Path $evidence 'flutter.log')
        $result = $LASTEXITCODE
    } finally { Pop-Location }
} finally {
    $env:HERMES_HOME = $previousHome
    if ($backend -and !$KeepBackend) {
        # Stop only the process tree created above, including its MCP child.
        $backend.Refresh()
        if (!$backend.HasExited) {
            & taskkill.exe /PID $backend.Id /T /F | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not stop the owned QA backend; its home was retained.' }
        }
        & $adb -s $Device reverse --remove "tcp:$port"
        $resolved = [IO.Path]::GetFullPath($qaHome)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (!$resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -ne $run) { throw 'QA cleanup path mismatch' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
exit $result
