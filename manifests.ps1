# جمع كل عمليات التحميل في مصفوفة
$downloadJobs = @()
foreach ($lua in $luaFiles) {
    $AppId = [regex]::Match($lua.Name,'(\d+)\.lua').Groups[1].Value
    $depots = Get-DepotIdsFromLua $lua.FullName
    $appInfo = Get-AppInfo $AppId
    if ($appInfo -and $appInfo.status -eq "success") {
        foreach ($DepotId in $depots) {
            $ManifestId = Get-ManifestIdForDepot $appInfo $AppId $DepotId
            if ($ManifestId) {
                $downloadJobs += [PSCustomObject]@{DepotId=$DepotId; ManifestId=$ManifestId}
            }
        }
    }
}

# نبدأ Jobs للتحميل (بدون -Parallel)
$jobs = @()
$MaxParallel = 20  # أقصى عدد تحميلات متزامنة
foreach ($job in $downloadJobs) {
    $jobs += Start-Job -ScriptBlock {
        param($DepotId,$ManifestId,$depotCachePath,$resolvedMode,$activeApiKey)

        $outFile = Join-Path $depotCachePath "${DepotId}_${ManifestId}.manifest"
        $githubUrl = "https://raw.githubusercontent.com/qwe213312/k25FCdfEOoEJ42S6/main/${DepotId}_${ManifestId}.manifest"

        try {
            Invoke-WebRequest -Uri $githubUrl -OutFile $outFile -TimeoutSec 120 -ErrorAction Stop
            Write-Host "Depot $DepotId OK" -ForegroundColor Green
        } catch {
            Write-Host "Depot $DepotId Failed" -ForegroundColor Red
        }

    } -ArgumentList $job.DepotId,$job.ManifestId,$depotCachePath,$resolvedMode,$activeApiKey

    # ننتظر لو وصلنا الحد الأقصى من الـJobs
    if ($jobs.Count -ge $MaxParallel) {
        $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job
        $jobs = @()
    }
}

# استكمال أي Jobs متبقية
if ($jobs.Count -gt 0) {
    $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
}

Write-Host "`nAll downloads finished!"
