param([int]$VinaPid = 0, [string]$PosesDir = 'docking_results\poses', [string]$OutputCsv = 'docking_results\best_affinity.csv', [string]$StatusFile = 'docking_results\summary_status.txt')

$ErrorActionPreference = 'Stop'
if ($VinaPid -gt 0) { try { Wait-Process -Id $VinaPid -ErrorAction Stop } catch { } }

$rows = foreach ($f in Get-ChildItem -LiteralPath $PosesDir -File -Filter '*.pdbqt') {
    $lines = Get-Content -LiteralPath $f.FullName -TotalCount 20
    $resultLine = $lines | Where-Object { $_ -match '^REMARK VINA RESULT:' } | Select-Object -First 1
    $nameLine = $lines | Where-Object { $_ -match '^REMARK\s+Name\s*=' } | Select-Object -First 1
    $affinity = $null
    if ($resultLine -and $resultLine -match 'RESULT:\s+(-?\d+(?:\.\d+)?)') { $affinity = [double]$Matches[1] }
    if ($null -ne $affinity) {
        $name = if ($nameLine -and $nameLine -match '^REMARK\s+Name\s*=\s*(.*)$') { $Matches[1].Trim() } else { '' }
        [PSCustomObject]@{ File=$f.BaseName; LigandName=$name; BestAffinity_kcal_mol=$affinity }
    }
}
$rows | Sort-Object BestAffinity_kcal_mol | Export-Csv -NoTypeInformation -Encoding UTF8 $OutputCsv
"completed=$($rows.Count) time=$(Get-Date -Format s)" | Set-Content -Encoding utf8 $StatusFile




