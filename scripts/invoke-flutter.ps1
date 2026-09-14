param(
    [Parameter(Mandatory = $true)][string]$ToolchainRoot,
    [ValidateRange(0, 300)][int]$BootstrapWaitSeconds = 30,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArguments
)
$ErrorActionPreference = 'Stop'
$flutter = Join-Path $ToolchainRoot 'flutter\bin\flutter.bat'
$cache = Join-Path $ToolchainRoot 'flutter\bin\cache'
if (!(Test-Path -LiteralPath $flutter -PathType Leaf)) {
    throw "Flutter was not found: $flutter"
}
# Flutter's Windows bootstrap retries this lock without sleeping. Check write
# access before entering the batch file, and bound a busy-lock wait ourselves.
# OpenOrCreate preserves an existing lock file; never delete a Flutter lock.
$timer = [Diagnostics.Stopwatch]::StartNew()
while ($true) {
    $probe = $null
    try {
        [IO.Directory]::CreateDirectory($cache) | Out-Null
        $probe = [IO.File]::Open(
            (Join-Path $cache 'flutter.bat.lock'),
            [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None
        )
        break
    } catch [UnauthorizedAccessException] {
        throw "Flutter requires write access to its SDK cache: $cache. Run with permission to write that directory; retrying the batch launcher cannot fix access denied."
    } catch [IO.IOException] {
        $nativeCode = $_.Exception.HResult -band 0xFFFF
        if ($nativeCode -notin @(32, 33)) { throw }
        if ($timer.Elapsed.TotalSeconds -ge $BootstrapWaitSeconds) {
            throw "Flutter's SDK bootstrap lock is busy after ${BootstrapWaitSeconds}s. Let the existing SDK operation finish, then retry."
        }
        Start-Sleep -Milliseconds 200
    } finally {
        if ($null -ne $probe) { $probe.Dispose() }
    }
}
# The SDK still owns locking during bootstrap. This preflight cannot prevent a
# different process from acquiring its lock between this check and invocation.
& $flutter @FlutterArguments
exit $LASTEXITCODE