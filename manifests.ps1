# Steam Manifest Downloader - Auto AppID + Depot detection

param(
    [string]$ApiKey,
    [string]$MorrenusApiKey,
    [switch]$UseMainAPI
)

# ============== GLOBAL CONFIG ==============
$Global:Mode = "github"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "Steam Manifest Downloader (Auto AppID)"
$luaFolder = "C:\Program Files (x86)\Steam\config\stplug-in"
# ===========================================

function Write-Status { param($msg,$color="White"); Write-Host "  [*] $msg" -ForegroundColor $color }
function Write-Success { param($msg); Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-ErrorMsg { param($msg); Write-Host "  [-] $msg" -ForegroundColor Red }

function Get-SteamPath {
    $paths = @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKCU:\SOFTWARE\Valve\Steam")
    foreach ($p in $paths) { try { $steam = (Get-ItemProperty -Path $p -ErrorAction SilentlyContinue).InstallPath; if ($steam -and (Test-Path $steam)) { return $steam } } catch{} }
    return $null
}

function Get-DepotIdsFromLua { param($LuaPath); $depots=@(); $content=Get-Content $LuaPath; foreach ($line in $content) { if ($line -match 'addappid\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*"[a-fA-F0-9]+"') { $depots+=$matches[1] } } ; return $depots|Select-Object -Unique }

function Get-AppInfo { param($AppId); try { return Invoke-RestMethod -Uri "https://api.steamcmd.net/v1/info/$AppId" -Method Get -TimeoutSec 30 } catch { return $null } }

function Get-ManifestIdForDepot { param($AppInfo,$AppId,$DepotId); try { $depots=$AppInfo.data.$AppId.depots; if ($depots.$DepotId -and $depots.$DepotId.manifests -and $depots.$DepotId.manifests.public) { return $depots.$DepotId.manifests.public.gid } } catch{}; return $null }

function Try-DownloadUrl { param($Url,$OutputFile,$MaxRetries=3); for ($i=1;$i -le $MaxRetries;$i++) { try { if (Test-Path $OutputFile){Remove-Item $OutputFile -Force}; Invoke-WebRequest -Uri $Url -Method Get -TimeoutSec 120 -OutFile $OutputFile -ErrorAction Stop; if ((Get-Item $OutputFile).Length -gt 0){ return $true } } catch { if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { if (Test-Path $OutputFile){Remove-Item $OutputFile -Force}; return $false } } Start-Sleep -Seconds 2 }; return $false }

function Download-Manifest { param($DepotId,$ManifestId,$OutputPath,$Mode,$ApiKey)
    $outFile = Join-Path $OutputPath "${DepotId}_${ManifestId}.manifest"
    $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"
    if (Try-DownloadUrl $githubUrl $outFile) { Write-Success "Depot $DepotId downloaded from GitHub"; return }
    if ($Mode -eq "github+manifesthub") { $url="https://api.manifesthub1.filegear-sg.me/manifest?apikey=$ApiKey&depotid=$DepotId&manifestid=$ManifestId"; if (Try-DownloadUrl $url $outFile) { Write-Success "Depot $DepotId downloaded from ManifestHub"; return } }
    Write-ErrorMsg "Depot $DepotId failed to download"
}

# ================== MAIN ==================
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

foreach ($lua in $luaFiles) {
    $AppId = [regex]::Match($lua.Name,'(\d+)\.lua').Groups[1].Value
    Write-Host "`n================ Processing AppID $AppId ================"
    $depots = Get-DepotIdsFromLua $lua.FullName
    if ($depots.Count -eq 0) { Write-Warning "No depots found in $($lua.Name)"; continue }
    Write-Host "Found depots: $($depots -join ', ')"

    $appInfo = Get-AppInfo $AppId
    if (-not $appInfo -or $appInfo.status -ne "success") { Write-Warning "Failed to fetch app info for $AppId"; continue }

    foreach ($DepotId in $depots) {
        $ManifestId = Get-ManifestIdForDepot $appInfo $AppId $DepotId
        if ($ManifestId) {
            Download-Manifest -DepotId $DepotId -ManifestId $ManifestId -OutputPath $depotCachePath -Mode $resolvedMode -ApiKey $activeApiKey
        } else {
            Write-Warning "No manifest ID found for depot $DepotId"
        }
    }
}

Write-Host "`nAll Lua files processed. Manifests are in $depotCachePath"
