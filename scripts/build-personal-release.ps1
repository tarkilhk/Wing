param(
    [Parameter(Mandatory = $true)][string]$ToolchainRoot,
    [string]$SigningDirectory = (Join-Path $env:LOCALAPPDATA 'HermesPersonal\signing'),
    [string]$FirebaseOptionsFile,
    # Enable R8/code and resource shrinking for a smaller distribution APK.
    # Personal iteration still uses Flutter's release AOT compiler without it.
    [switch]$OptimizeAndroid,
    # Build a signed Personal development APK without Dart AOT compilation.
    [switch]$Development,
    [switch]$InitializeSigning
)
$ErrorActionPreference = 'Stop'
if ($Development -and $OptimizeAndroid) { throw '-Development and -OptimizeAndroid cannot be combined' }
# Run Flutter tests before this script, not concurrently: both commands can
# regenerate Android's plugin registry with different dev-dependency settings.
$repository = Split-Path $PSScriptRoot -Parent
$signingRoot = [IO.Path]::GetFullPath($SigningDirectory)
$keystore = Join-Path $signingRoot 'hermes-personal.p12'
$credentialFile = Join-Path $signingRoot 'password.dpapi.xml'
$keytool = Join-Path $ToolchainRoot 'jdk-17\bin\keytool.exe'
$flutter = Join-Path $ToolchainRoot 'flutter\bin\flutter.bat'
$sdk = Join-Path $ToolchainRoot 'android-sdk'
$buildTools = Join-Path $sdk 'build-tools\36.0.0'
$firebaseBuildArguments = @()
if ($FirebaseOptionsFile) {
    $firebaseOptionsPath = (Resolve-Path -LiteralPath $FirebaseOptionsFile -ErrorAction Stop).Path
    $firebaseBuildArguments = @("--dart-define-from-file=$firebaseOptionsPath")
}
foreach ($required in @($keytool, $flutter, (Join-Path $buildTools 'apksigner.bat'))) {
    if (!(Test-Path -LiteralPath $required)) { throw 'Required release tool is missing' }
}
if ($signingRoot.StartsWith($repository + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing material must live outside the repository'
}
if ($InitializeSigning) {
    if (Test-Path -LiteralPath $signingRoot) { throw 'Signing directory already exists; refusing to replace any signing material' }
    New-Item -ItemType Directory -Path $signingRoot | Out-Null
    $principal = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $signingRoot /inheritance:r /grant:r "${principal}:(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict signing-directory permissions' }
    $random = [byte[]]::new(32)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($random) } finally { $generator.Dispose() }
    $password = ConvertTo-SecureString ([Convert]::ToBase64String($random)) -AsPlainText -Force
    $credential = [PSCredential]::new('hermes-personal', $password)
    # Windows DPAPI binds this to this user/computer. Not a portable backup.
    $credential | Export-Clixml -LiteralPath $credentialFile
    try {
        $env:HERMES_STORE_PASSWORD = $credential.GetNetworkCredential().Password
        & $keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias hermes-personal -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Hermes Personal' -storepass:env HERMES_STORE_PASSWORD -keypass:env HERMES_STORE_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw 'Signing key generation failed; do not delete or overwrite partial signing material automatically' }
    } finally { Remove-Item Env:HERMES_STORE_PASSWORD -ErrorAction SilentlyContinue }
}
if (!(Test-Path -LiteralPath $keystore) -or !(Test-Path -LiteralPath $credentialFile)) {
    throw 'Signing material is missing; initialize once with -InitializeSigning'
}
$credential = Import-Clixml -LiteralPath $credentialFile
# All personal releases share one lock, even when called from separate snapshots.
$buildMutex = [Threading.Mutex]::new($false, 'Local\HermesPersonalAndroidReleaseBuild')
$ownsBuildMutex = $false
$pushedLocation = $false
try {
    try { $ownsBuildMutex = $buildMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsBuildMutex = $true }
    if (!$ownsBuildMutex) { throw 'Another personal release build is running. Let it finish before starting another.' }
    $buildRepository = $repository
    Write-Output "Release workspace: $buildRepository"
    Push-Location $buildRepository
    $pushedLocation = $true
    $env:JAVA_HOME = Join-Path $ToolchainRoot 'jdk-17'
    $env:ANDROID_SDK_ROOT = $sdk
    $env:HERMES_STORE_FILE = $keystore
    $env:HERMES_STORE_PASSWORD = $credential.GetNetworkCredential().Password
    $env:HERMES_KEY_ALIAS = $credential.UserName
    $env:HERMES_KEY_PASSWORD = $env:HERMES_STORE_PASSWORD
    $buildMode = 'release'
    $androidBuildArguments = @('--release', '--split-debug-info=build/personal-symbols', '--android-project-arg=shrink=false')
    if ($Development) {
        $buildMode = 'debug'
        $androidBuildArguments = @('--debug', '--android-project-arg=hermesPersonalDevelopment=true')
        Write-Output 'Personal development APK: Dart JIT, assertions and debugging enabled; larger APK and slower runtime than release.'
    } elseif ($OptimizeAndroid) {
        $androidBuildArguments = @('--release', '--split-debug-info=build/personal-symbols')
        Write-Output 'Android code and resource optimization enabled.'
    } else {
        Write-Output 'Faster personal build: Android shrinking disabled; Dart release compilation and Android Lint remain enabled.'
    }
    # Flutter 3.44 skips release-specific plugin regeneration with --no-pub.
    # Keep pub so the native plugin registry matches this build mode.
    $buildTimer = [Diagnostics.Stopwatch]::StartNew()
    $flutterArguments = @('build', 'apk', '--target-platform', 'android-arm64', '--split-per-abi', '-t', 'lib/main.dart') + $firebaseBuildArguments + $androidBuildArguments
    & (Join-Path $PSScriptRoot 'invoke-flutter.ps1') -ToolchainRoot $ToolchainRoot -FlutterArguments $flutterArguments
    if ($LASTEXITCODE -ne 0) { throw "Personal $buildMode build failed" }
    $buildTimer.Stop()
    Write-Output "Flutter build including dependency resolution: $([math]::Round($buildTimer.Elapsed.TotalSeconds, 1))s"
    $apk = Join-Path $buildRepository "build\app\outputs\flutter-apk\app-arm64-v8a-$buildMode.apk"
    $signature = & (Join-Path $buildTools 'apksigner.bat') verify --verbose --print-certs $apk
    if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
    $expectedCertificate = (Get-Content (Join-Path $repository 'android\personal-release-certificate.sha256') -Raw).Trim()
    if ($signature -notcontains "Signer #1 certificate SHA-256 digest: $expectedCertificate") {
        throw 'APK was signed with a different key than the personal release identity'
    }
    $signature | Write-Output
    $badging = & (Join-Path $buildTools 'aapt.exe') dump badging $apk
    if ($LASTEXITCODE -ne 0 -or !($badging -match "package: name='com.tarkilhk.hermes.android'")) { throw 'Unexpected APK identity' }
    $isDebuggable = [bool]($badging -match '^application-debuggable')
    if ($Development -and !$isDebuggable) { throw 'Development APK is not debuggable' }
    if (!$Development -and $isDebuggable) { throw 'Release APK is debuggable' }
    $badging | Select-String '^(package:|application-label:|launchable-activity:|native-code:)'
    Write-Output "Verified personal $buildMode APK: $apk"
} finally {
    foreach ($name in @('HERMES_STORE_FILE', 'HERMES_STORE_PASSWORD', 'HERMES_KEY_ALIAS', 'HERMES_KEY_PASSWORD')) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    if ($pushedLocation) { Pop-Location }
    if ($ownsBuildMutex) { $buildMutex.ReleaseMutex() }
    $buildMutex.Dispose()
}
