# =============================================
# Steam Depot Manifest Downloader
# =============================================

$steamPath = "C:\Program Files (x86)\Steam"
$luaFolder = "$steamPath\config\stplug-in"
$output = "$steamPath\depotcache"

# مفتاح ManifestHub (أدخل مفتاحك هنا)
$manifestHubKey = "PUT_YOUR_REAL_KEY_HERE"

# إنشاء مجلد الإخراج إذا غير موجود
if (-not (Test-Path $output)) {
    New-Item -ItemType Directory $output | Out-Null
}

# احصل على كل ملفات Lua (AppIDs)
$apps = Get-ChildItem $luaFolder -Filter *.lua

foreach ($app in $apps) {

    $appId = [System.IO.Path]::GetFileNameWithoutExtension($app.Name)
    Write-Host "`nProcessing AppID $appId ..."

    $content = Get-Content $app.FullName
    $depots = @()

    # استخراج depot IDs من Lua
    foreach ($line in $content) {
        if ($line -match 'addappid\s*\(\s*(\d+)') {
            $depots += $matches[1]
        }
    }

    $depots = $depots | Select-Object -Unique

    # جلب App Info
    try {
        $info = Invoke-RestMethod "https://api.steamcmd.net/v1/info/$appId" -TimeoutSec 60
    } catch {
        Write-Host "Failed to get app info for AppID $appId"
        continue
    }

    foreach ($depot in $depots) {

        $manifest = $info.data.$appId.depots.$depot.manifests.public.gid

        # تجاهل depots بدون manifest لتسريع
        if (-not $manifest) {
            Write-Host "No manifest found for Depot $depot, skipping."
            continue
        }

        $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${depot}_${manifest}.manifest"
        $manifestHubUrl = "https://api.manifesthub1.filegear-sg.me/manifest?apikey=$manifestHubKey&depotid=${depot}&manifestid=${manifest}"
        $file = "$output\${depot}_${manifest}.manifest"

        # إذا الملف موجود، تخطي
        if (Test-Path $file) {
            if ((Get-Item $file).Length -gt 0) {
                Write-Host "Depot $depot already exists, skipping"
                continue
            }
        }

        # تنزيل من GitHub مع Retry
        $maxAttempts = 2
        $downloaded = $false

        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            try {
                Write-Host ("Downloading Depot {0} from GitHub (Attempt {1})..." -f $depot, $attempt)
                Invoke-WebRequest $githubUrl -OutFile $file -TimeoutSec 60
                $downloaded = $true
                Write-Host ("Depot {0} downloaded successfully from GitHub!" -f $depot)
                Start-Sleep -Seconds 1
                break
            } catch {
                Write-Host ("GitHub attempt {0} failed for Depot {1}: {2}" -f $attempt, $depot, $_.Exception.Message)
                Start-Sleep -Seconds ($attempt * 2)
            }
        }

        # إذا GitHub فشل، جرب ManifestHub
        if (-not $downloaded -and $manifestHubKey -ne "PUT_YOUR_REAL_KEY_HERE") {
            Write-Host ("Trying ManifestHub for Depot {0}..." -f $depot)
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Invoke-WebRequest $manifestHubUrl -OutFile $file -TimeoutSec 60
                    Write-Host ("Depot {0} downloaded successfully from ManifestHub!" -f $depot)
                    Start-Sleep -Seconds 1
                    break
                } catch {
                    Write-Host ("ManifestHub attempt {0} failed for Depot {1}: {2}" -f $attempt, $depot, $_.Exception.Message)
                    Start-Sleep -Seconds ($attempt * 2)
                }
            }
        }
    }
}

Write-Host "`nALL DONE!"
