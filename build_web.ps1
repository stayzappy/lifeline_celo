# Stop on error
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " LifeLine Protocol Builder (Dart2JS)"
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Build version
$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Write-Host "[INFO] Build Version: $timestamp"

# Run Flutter build (No Wasm)
Write-Host "[INFO] Running Flutter build..."

flutter build web `
--release `
--tree-shake-icons `
--dart2js-optimization O4 `
--no-source-maps `
--pwa-strategy none

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter build failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "[INFO] Flutter build completed."

$webDir = "build\web"
$indexPath = "$webDir\index.html"

if (!(Test-Path $indexPath)) {
    Write-Host "[ERROR] index.html not found!" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Starting asset fingerprinting (Redundancy)..."

function Get-ShortHash($file) {
    $hash = (Get-FileHash $file -Algorithm SHA256).Hash
    return $hash.Substring(0,10).ToLower()
}

$renameMap = @{}

# STAGE 1: Hash the core JS files first
$coreFiles = @(
    "$webDir\main.dart.js",
    "$webDir\flutter.js"
)

foreach ($file in $coreFiles) {
    if (!(Test-Path $file)) { continue }

    $hash = Get-ShortHash $file
    $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $ext = [System.IO.Path]::GetExtension($file)
    
    $newName = "$name.$hash$ext"
    $newPath = Join-Path $webDir $newName

    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $file $newPath -Force

    $renameMap[[System.IO.Path]::GetFileName($file)] = $newName
    Write-Host "[HASH] $name -> $newName"
}

# STAGE 2: Update references INSIDE flutter_bootstrap.js before hashing it
$bootstrapPath = "$webDir\flutter_bootstrap.js"
if (Test-Path $bootstrapPath) {
    Write-Host "[INFO] Syncing internal Wasm/JS references..."
    $bootText = Get-Content $bootstrapPath -Raw
    foreach ($key in $renameMap.Keys) {
        $bootText = $bootText.Replace($key, $renameMap[$key])
    }
    Set-Content $bootstrapPath $bootText -Encoding UTF8

    # Now hash the bootstrap file itself
    $hash = Get-ShortHash $bootstrapPath
    $newName = "flutter_bootstrap.$hash.js"
    $newPath = Join-Path $webDir $newName
    
    if (Test-Path $newPath) { Remove-Item $newPath -Force }
    Move-Item $bootstrapPath $newPath -Force
    
    $renameMap["flutter_bootstrap.js"] = $newName
    Write-Host "[HASH] flutter_bootstrap -> $newName"
}

Write-Host "[INFO] Updating index.html with telemetry and hashes..."

$html = Get-Content $indexPath -Raw

# Update all references in HTML
foreach ($key in $renameMap.Keys) {
    $html = $html.Replace($key, $renameMap[$key])
}

if ($html -notmatch "rel=`"preconnect`"") {
    $preconnect = '<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>'
    $html = $html.Replace("</head>", "$preconnect`n</head>")
}

# Inject Telemetry Loading Screen (LifeLine Protocol Glass UX)
$loadingDiv = @"
<div id="loading">
<style>
body { margin:0; background:#071310; display:flex; justify-content:center; align-items:center; height:100vh; font-family: 'DM Sans', sans-serif; color:#F0EBE0; overflow:hidden; }
.glass-panel { background: rgba(13, 31, 24, 0.6); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid rgba(53, 208, 127, 0.15); border-radius: 24px; padding: 40px 48px; display: flex; flex-direction: column; align-items: center; box-shadow: 0 24px 48px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.05); }
.shield-icon { width: 42px; height: 42px; margin-bottom: 24px; animation: pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite; }
.progress-container { width: 180px; height: 3px; background: rgba(255,255,255,0.08); border-radius: 4px; overflow: hidden; margin-bottom: 16px; position: relative; }
.progress-fill { width: 40%; height: 100%; background: #35D07F; border-radius: 4px; position: absolute; left: 0; top: 0; animation: sweep 1.5s ease-in-out infinite; }
.loading-text { font-size: 11px; font-weight: 600; letter-spacing: 2.5px; color: #35D07F; text-transform: uppercase; font-family: 'Space Mono', monospace; }
.error-text { color: #F46B6B !important; }
@keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); filter: drop-shadow(0 0 12px rgba(53,208,127,0.4)); } 50% { opacity: 0.6; transform: scale(0.95); filter: drop-shadow(0 0 0px rgba(53,208,127,0)); } }
@keyframes sweep { 0% { transform: translateX(-100%); } 100% { transform: translateX(250%); } }
</style>
<div class="glass-panel">
    <svg class="shield-icon" viewBox="0 0 24 24" fill="none" stroke="#35D07F" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 2L4 6v6c0 5.5 3.5 9.7 8 11 4.5-1.3 8-5.5 8-11V6L12 2z" />
    </svg>
    <div class="progress-container" id="loader-bar">
        <div class="progress-fill" id="loader-fill"></div>
    </div>
    <div class="loading-text" id="loading-title">ESTABLISHING LIFELINE...</div>
</div>
</div>
<script>
    function logBoot(msg, isError = false) {
        if (isError) {
            console.error('[LifeLine Boot] ' + msg);
        } else {
            console.log('[LifeLine Boot] ' + msg);
        }
    }

    window.addEventListener('error', function(e) {
        logBoot('FATAL ERROR: ' + e.message + ' at ' + e.filename + ':' + e.lineno, true);
        document.getElementById('loading-title').innerText = 'SECURE BOOT FAILED';
        document.getElementById('loading-title').className = 'loading-text error-text';
        document.getElementById('loader-fill').style.background = '#F46B6B';
        document.getElementById('loader-fill').style.animation = 'none';
        document.getElementById('loader-fill').style.width = '100%';
        document.querySelector('.shield-icon').style.stroke = '#F46B6B';
        document.querySelector('.shield-icon').style.animation = 'none';
    });

    logBoot('HTML Parsed. Synchronizing JS Engine...');

    window.addEventListener('flutter-first-frame', function() {
        logBoot('Encrypted frame rendered. Destroying telemetry UI...');
        document.getElementById('loading').style.transition = 'opacity 0.6s ease';
        document.getElementById('loading').style.opacity = '0';
        setTimeout(function() {
            var loader = document.getElementById('loading');
            if (loader) loader.remove();
        }, 600);
    });
</script>
"@

if ($html -notmatch "id=`"loading`"") {
    $html = $html.Replace("<body>", "<body>`n$loadingDiv")
}

$buildLog = "<script>console.log('LifeLine Build Version: $timestamp');</script>"
$html = $html.Replace("</head>", "$buildLog`n</head>")

Set-Content $indexPath $html -Encoding UTF8
Write-Host "[INFO] index.html optimized with telemetry."

Write-Host "[INFO] Compressing assets..."
Get-ChildItem $webDir -Recurse -Include *.js,*.json | ForEach-Object {
    $gzipPath = "$($_.FullName).gz"
    $input = [IO.File]::OpenRead($_.FullName)
    $output = [IO.File]::Create($gzipPath)
    $gzip = New-Object IO.Compression.GzipStream($output, [IO.Compression.CompressionMode]::Compress)
    $input.CopyTo($gzip)
    $gzip.Close()
    $input.Close()
    $output.Close()
    Write-Host "[GZIP] $($_.Name)"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " SECURE BUILD SUCCESSFUL"
Write-Host " Location: build/web"
Write-Host " Version: $timestamp"
Write-Host "========================================" -ForegroundColor Green
Write-Host ""