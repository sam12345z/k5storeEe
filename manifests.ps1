<#
.SYNOPSIS
    Steam Manifest Downloader - Ultra Fast Parallel
.DESCRIPTION
    Automatically detects all AppIDs from Lua files, downloads all depot manifests in ultra-parallel mode.
.PARAMETER ApiKey
    ManifestHub API key (if using github+manifesthub mode)
.PARAMETER UseMainAPI
    Force use github+manifesthub mode
#>

param(
    [string]$ApiKey,
    [switch]$UseMainAPI
)

# ===== CONFIG =====
$Global:Mode = "github"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$luaFolder = "C:\Program Files (x86)\Steam\config\stplug-in"
$MaxParallel = 50  # جنوني جدًا!  
# ==================

function Write-Status { param($msg,$color="White"); Write-Host "  [*] $msg" -ForegroundColor $color }
function Write-Success { param($msg); Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-ErrorMsg { param($msg); Write-Host "  [-] $msg" -ForegroundColor Red }

function Get-SteamPath {
    $paths = @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKCU:\SOFTWARE\Valve\Steam")
    foreach ($p in $paths) {
        try { $steam = (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue).InstallPath; if ($steam -and (Test-Path $steam)) { return $steam } } catch{}
    }
    return $null
}

function Get-DepotIdsFromLua {
    param($LuaPath)
    $depots=@()
    $content=Get-Content $LuaPath
    foreach ($line in $content) { 
        if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') { $depots+=$matches[1] } 
    }
    return $depots|Select-Object -Unique
}

function Get-AppInfo { param($AppId); try { return Invoke-RestMethod -Uri "https://api.steamcmd.net/v1/info/$AppId" -Method Get -TimeoutSec 30 } catch { return $null } }

function Get-ManifestIdForDepot { param($AppInfo,$AppId,$DepotId)
    try { $depots=$AppInfo.data.$AppId.depots; if ($depots.$DepotId -and $depots.$DepotId.manifests -and $depots.$DepotId.manifests.public) { return $depots.$DepotId.manifests.public.gid } } catch{}; return $null
}

function Download-Depot {
    param($DepotId,$ManifestId,$depotCachePath,$resolvedMode,$activeApiKey)
    $outFile = Join-Path $depotCachePath "${DepotId}_${ManifestId}.manifest"
    $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"
    try {
        Invoke-WebRequest -Uri $githubUrl -OutFile $outFile -TimeoutSec 120 -ErrorAction Stop
        Write-Success "Depot $DepotId downloaded from GitHub"
    } catch {
        if ($resolvedMode -eq "github+manifesthub") {
            $url="https://api.manifesthub1.filegear-sg.me/manifest?apikey=$activeApiKey&depotid=$DepotId&manifestid=$ManifestId"
            try { Invoke-WebRequest -Uri $url -OutFile $outFile -TimeoutSec 120 -ErrorAction Stop; Write-Success "Depot $DepotId downloaded from ManifestHub" } catch { Write-ErrorMsg "Depot $DepotId failed" }
        } else { Write-ErrorMsg "Depot $DepotId failed" }
    }
}

# ===== MAIN =====
Write-Status "Locating Steam installation..."
$steamPath = Get-SteamPath
if (-not $steamPath) { Write-ErrorMsg "Steam not found!"; exit 1 }
Write-Success "Steam found at $steamPath"

if (-not (Test-Path $luaFolder)) { Write-ErrorMsg "Lua folder not found: $luaFolder"; exit 1 }

$luaFiles = Get-ChildItem -Path $luaFolder -Filter *.lua
if ($luaFiles.Count -eq 0) { Write-ErrorMsg "No Lua files found in $luaFolder"; exit 1 }

Write-Status "Found $($luaFiles.Count) Lua file(s), processing..."

$depotCachePath = Join-Path $steamPath "depotcache"
if (-not (Test-Path $depotCachePath)) { New-Item -ItemType Directory -Path $depotCachePath | Out-Null }

$resolvedMode = $Global:Mode
if ($UseMainAPI) { $resolvedMode="github+manifesthub" }
$activeApiKey = $ApiKey
if (-not $activeApiKey) { $activeApiKey=$env:MH_API_KEY }

# Collect all download jobs
$downloadJobs = @()
foreach ($lua in $luaFiles) {
    $AppId = [regex]::Match($lua.Name,'(\d+)\.lua').Groups[1].Value
    Write-Host "`n================ Processing AppID $AppId ================"
    $depots = Get-DepotIdsFromLua $lua.FullName
    if ($depots.Count -eq 0) { Write-Host "No depots found in $($lua.Name)"; continue }
    Write-Host "Found depots: $($depots -join ', ')"

    $appInfo = Get-AppInfo $AppId
    if (-not $appInfo -or $appInfo.status -ne "success") { Write-Host "Failed to fetch app info for $AppId"; continue }

    foreach ($DepotId in $depots) {
        $ManifestId = Get-ManifestIdForDepot $appInfo $AppId $DepotId
        if ($ManifestId) {
            $downloadJobs += @{
                DepotId = $DepotId
                ManifestId = $ManifestId
            }
        } else { Write-Host "No manifest ID found for depot $DepotId" }
    }
}

Write-Status "`nStarting ultra-parallel downloads ($($downloadJobs.Count) depots)..."

# ==== Ultra Parallel using ForEach-Object -Parallel ====
$downloadJobs | ForEach-Object -Parallel {
    param($job,$depotCachePath,$resolvedMode,$activeApiKey)
    Download-Depot -DepotId $job.DepotId -ManifestId $job.ManifestId -depotCachePath $depotCachePath -resolvedMode $resolvedMode -activeApiKey $activeApiKey
} -ThrottleLimit $MaxParallel -ArgumentList $depotCachePath,$resolvedMode,$activeApiKey

Write-Host "`nAll downloads completed! Manifests are in $depotCachePath"
