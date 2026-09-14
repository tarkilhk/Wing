$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$runner = Join-Path $repository 'scripts\invoke-flutter.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('hermes-flutter-launcher-' + [guid]::NewGuid().ToString('N'))
$bin = Join-Path $fixture 'flutter\bin'
$cache = Join-Path $bin 'cache'
[IO.Directory]::CreateDirectory($cache) | Out-Null
$launcher = Join-Path $bin 'flutter.bat'
$lockFile = Join-Path $cache 'flutter.bat.lock'
try {
    [IO.File]::WriteAllText($launcher, "@echo off`r`necho launcher-ran %*`r`nexit /b 7`r`n")
    $output = & $runner -ToolchainRoot $fixture -FlutterArguments @('--version')
    if ($LASTEXITCODE -ne 7 -or $output -notmatch 'launcher-ran --version') {
        throw 'Flutter arguments or exit code were not preserved'
    }
    [IO.File]::WriteAllText($lockFile, 'preserve existing contents')
    $null = & $runner -ToolchainRoot $fixture -FlutterArguments @('--version')
    if ([IO.File]::ReadAllText($lockFile) -ne 'preserve existing contents') {
        throw 'The SDK lock contents were changed'
    }
    $held = [IO.File]::Open($lockFile, 'Open', 'ReadWrite', 'None')
    try {
        $caught = $false
        $timer = [Diagnostics.Stopwatch]::StartNew()
        try { & $runner -ToolchainRoot $fixture -BootstrapWaitSeconds 1 -FlutterArguments @('--version') }
        catch { if ($_ -notmatch 'bootstrap lock is busy') { throw }; $caught = $true }
        if (!$caught -or $timer.Elapsed.TotalSeconds -gt 5) { throw 'Busy SDK lock did not fail within its bounded wait' }
    } finally { $held.Dispose() }
    [IO.File]::SetAttributes($lockFile, [IO.FileAttributes]::ReadOnly)
    try {
        $caught = $false
        try { & $runner -ToolchainRoot $fixture -FlutterArguments @('--version') }
        catch { if ($_ -notmatch 'write access to its SDK cache') { throw }; $caught = $true }
        if (!$caught) { throw 'Unwritable SDK lock did not fail before launching Flutter' }
    } finally { [IO.File]::SetAttributes($lockFile, [IO.FileAttributes]::Normal) }
    Write-Output 'PASS: arguments, exit code, lock preservation, busy-lock timeout, and denied-write handling'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        !(Split-Path $resolved -Leaf).StartsWith('hermes-flutter-launcher-')) {
        throw 'Unexpected fixture cleanup path'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}