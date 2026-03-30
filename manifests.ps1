# AUTO Steam Manifest Downloader (All Lua files)

param(
    [string]$ApiKey,
    [switch]$UseMainAPI
)

$steamPath = "C:\Program Files (x86)\Steam"
$luaFolder = "$steamPath\config\stplug-in"
$outputPath = "$steamPath\depotcache"

if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

function Get-DepotIdsFromLua {
    param($path)
    $depots = @()
    foreach ($line in Get-Content $path) {
        if ($line -match 'addappid\s*\(\s*(\d+)') {
            $depots += $matches[1]
        }
    }
    return $depots | Select-Object -Unique
}

function Get-AppInfo {
    param($AppId)
    try {
        return Invoke-RestMethod "https://api.steamcmd.net/v1/info/$AppId"
    } catch { return $null }
}

function Get-ManifestId {
    param($app,$AppId,$DepotId)
    try {
        return $app.data.$AppId.depots.$DepotId.manifests.public.gid
    } catch { return $null }
}

function Download-Manifest {
    param($DepotId,$ManifestId)

    $file = "$outputPath\${DepotId}_${ManifestId}.manifest"

    # Skip if exists
    if (Test-Path $file) { return }

    $url1 = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"

    try {
        Invoke-WebRequest $url1 -OutFile $file -ErrorAction Stop
        if ((Get-Item $file).Length -gt 0) {
            Write-Host "[+] $DepotId GitHub" -ForegroundColor Green
            return
        }
    } catch {}

    # fallback ManifestHub
    if ($UseMainAPI -and $ApiKey) {
        $url2 = "https://api.manifesthub1.filegear-sg.me/manifest?apikey=$ApiKey&depotid=$DepotId&manifestid=$ManifestId"
        try {
            Invoke-WebRequest $url2 -OutFile $file -ErrorAction Stop
            Write-Host "[+] $DepotId API" -ForegroundColor Cyan
        } catch {
            Write-Host "[-] $DepotId FAILED" -ForegroundColor Red
        }
    }
}

# ================= MAIN =================

$luaFiles = Get-ChildItem $luaFolder -Filter *.lua

Write-Host "Found $($luaFiles.Count) games..." -ForegroundColor Yellow

$jobs = @()

foreach ($lua in $luaFiles) {

    $AppId = [regex]::Match($lua.Name,'\d+').Value
    Write-Host "`n=== AppID $AppId ===" -ForegroundColor Cyan

    $depots = Get-DepotIdsFromLua $lua.FullName
    $appInfo = Get-AppInfo $AppId

    if (-not $appInfo) {
        Write-Host "Failed AppID $AppId" -ForegroundColor Red
        continue
    }

    foreach ($DepotId in $depots) {
        $ManifestId = Get-ManifestId $appInfo $AppId $DepotId

        if ($ManifestId) {
            # تحميل متوازي (سريع 🔥)
            $jobs += Start-Job -ScriptBlock {
                param($d,$m,$p,$k,$useApi)

                $file = "$p\${d}_${m}.manifest"
                if (Test-Path $file) { return }

                try {
                    Invoke-WebRequest "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${d}_${m}.manifest" -OutFile $file -ErrorAction Stop
                    if ((Get-Item $file).Length -gt 0) { return }
                } catch {}

                if ($useApi -and $k) {
                    try {
                        Invoke-WebRequest "https://api.manifesthub1.filegear-sg.me/manifest?apikey=$k&depotid=$d&manifestid=$m" -OutFile $file
                    } catch {}
                }

            } -ArgumentList $DepotId,$ManifestId,$outputPath,$ApiKey,$UseMainAPI
        }
    }
}

Write-Host "`nStarting downloads..." -ForegroundColor Yellow
Wait-Job $jobs
Write-Host "Done 🔥" -ForegroundColor Green
