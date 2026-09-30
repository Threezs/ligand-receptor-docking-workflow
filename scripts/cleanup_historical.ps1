param([string]$LigandRoot)

$ErrorActionPreference = 'Stop'
$root = (Get-Location).Path
if ([string]::IsNullOrWhiteSpace($LigandRoot)) { $LigandRoot = Join-Path $root 'ligand_data' }
$lig = [System.IO.Path]::GetFullPath($LigandRoot)
$summaryPath = Join-Path $lig 'summary.csv'
if (!(Test-Path -LiteralPath $summaryPath)) { throw 'summary.csv not found' }

$rows = Import-Csv -LiteralPath $summaryPath
$valid = @{}
foreach ($row in $rows) {
    if ($row.Status -in @('success', 'skipped_existing')) { $valid[$row.File] = $true }
}

$pdbDir = Join-Path $lig 'pdbqt'
$sdfDir = Join-Path $lig 'prepared_sdf'
$failedDir = Join-Path $lig 'failed'
$logsDir = Join-Path $lig 'logs'

$stalePdb = @(Get-ChildItem -LiteralPath $pdbDir -File -ErrorAction SilentlyContinue | Where-Object { !$valid.ContainsKey($_.BaseName) })
$staleSdf = @(Get-ChildItem -LiteralPath $sdfDir -File -ErrorAction SilentlyContinue | Where-Object { !$valid.ContainsKey($_.BaseName) })
$failedFiles = @(Get-ChildItem -LiteralPath $failedDir -File -ErrorAction SilentlyContinue)
$oldSummaries = @(Get-ChildItem -LiteralPath $lig -File -Filter 'summary_*test.csv' -ErrorAction SilentlyContinue)
$oldLogs = @(Get-ChildItem -LiteralPath $logsDir -File -ErrorAction SilentlyContinue)

foreach ($file in @($stalePdb + $staleSdf + $failedFiles + $oldSummaries + $oldLogs)) {
    $full = [System.IO.Path]::GetFullPath($file.FullName)
    $allowed = @([System.IO.Path]::GetFullPath($pdbDir), [System.IO.Path]::GetFullPath($sdfDir), [System.IO.Path]::GetFullPath($failedDir), [System.IO.Path]::GetFullPath($logsDir), [System.IO.Path]::GetFullPath($lig))
    if ($allowed | Where-Object { $full.StartsWith($_ + [System.IO.Path]::DirectorySeparatorChar) }) {
        Remove-Item -LiteralPath $full -Force
    }
}

Write-Output "deleted_stale_pdbqt=$($stalePdb.Count) stale_sdf=$($staleSdf.Count) failed_copies=$($failedFiles.Count) old_summaries=$($oldSummaries.Count) old_logs=$($oldLogs.Count)"
Write-Output "kept_valid_files=$($valid.Count)"

