# install.ps1 - Install or update LiveMD for the current user (Windows)
# Usage: irm https://raw.githubusercontent.com/erkantaylan/livemd/master/install.ps1 | iex

#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo        = 'erkantaylan/livemd'
$BinaryName  = 'livemd.exe'
$InstallDir  = Join-Path $env:LOCALAPPDATA 'Programs\livemd'
$InstallPath = Join-Path $InstallDir $BinaryName

function Write-Info($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err ($msg) { Write-Host "[x] $msg" -ForegroundColor Red }

function Get-Arch {
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'AMD64'  { return 'amd64' }
        'x86_64' { return 'amd64' }
        default {
            Write-Err "Unsupported architecture: $arch (only amd64 builds are published)"
            exit 1
        }
    }
}

function Get-LatestVersion {
    $url = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{ 'User-Agent' = 'livemd-installer' }
    return (Invoke-RestMethod -Uri $url -Headers $headers -UseBasicParsing).tag_name
}

function Add-ToUserPath($dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { $current = '' }
    $entries = $current -split ';' | Where-Object { $_ -ne '' }
    if ($entries -contains $dir) { return $false }
    $new = (@($entries) + $dir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $new, 'User')
    # Update current session too so verification right after install can find the binary.
    if (-not (($env:Path -split ';') -contains $dir)) {
        $env:Path = "$env:Path;$dir"
    }
    return $true
}

Write-Host ''
Write-Host 'LiveMD Installer' -ForegroundColor Cyan
Write-Host ''

$arch = Get-Arch
$platform = "windows-$arch"
Write-Info "Platform: $platform"

$version = Get-LatestVersion
if (-not $version) {
    Write-Err 'Could not determine latest version from GitHub.'
    exit 1
}
Write-Info "Latest version: $version"

# Stop any running instance so we can replace the .exe (Windows locks running binaries).
$existing = Get-Command $BinaryName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warn "Existing installation: $($existing.Source)"
    try {
        & $existing.Source stop *> $null
        Write-Info 'Stopped running server (if any).'
    } catch {
        # Server might not be running; ignore.
    }
    Start-Sleep -Milliseconds 800
}

$assetName   = "livemd-$platform.exe"
$downloadUrl = "https://github.com/$Repo/releases/download/$version/$assetName"
$tmp         = Join-Path $env:TEMP ("livemd-" + [guid]::NewGuid().ToString() + ".exe")

Write-Info "Downloading $assetName..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tmp -UseBasicParsing -Headers @{ 'User-Agent' = 'livemd-installer' }
} catch {
    Write-Err "Download failed: $($_.Exception.Message)"
    Write-Err "URL: $downloadUrl"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    exit 1
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

try {
    Move-Item -Path $tmp -Destination $InstallPath -Force
} catch {
    Write-Err "Could not install to $InstallPath - $($_.Exception.Message)"
    Write-Err 'Is livemd.exe still running? Close it and re-run the installer.'
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    exit 1
}
Write-Info "Installed to $InstallPath"

if (Add-ToUserPath $InstallDir) {
    Write-Info "Added $InstallDir to user PATH (open a new terminal to pick it up)."
} else {
    Write-Info "$InstallDir already in user PATH."
}

try {
    $installedVersion = (& $InstallPath version 2>$null) -join ' '
    if ($installedVersion) { Write-Info "Verified: $installedVersion" }
} catch {
    # version subcommand may not exist on older builds; non-fatal.
}

# Persist port if LIVEMD_PORT is set
if ($env:LIVEMD_PORT) {
    try {
        & $InstallPath port $env:LIVEMD_PORT *> $null
        Write-Info "Default port set to $($env:LIVEMD_PORT)"
    } catch {
        Write-Warn "Failed to set port to $($env:LIVEMD_PORT); using default."
    }
}

# Start the daemon
try {
    & $InstallPath start --detach
} catch {
    Write-Warn "Daemon did not start cleanly: $($_.Exception.Message)"
    Write-Warn "Run 'livemd start --detach' manually."
}

Write-Host ''
Write-Host "LiveMD $version installed." -ForegroundColor Green
Write-Host ''
Write-Host '  Watch a file:  livemd add README.md'
Write-Host '  List watched:  livemd list'
Write-Host '  Stop server:   livemd stop'
Write-Host '  Re-install:    re-run this command (idempotent - also updates)'
Write-Host ''
if ($existing -and $existing.Source -ne $InstallPath) {
    Write-Warn "Old binary still exists at $($existing.Source) - you may want to remove it."
}
