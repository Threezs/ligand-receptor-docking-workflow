param(
    [int]$ThrottleLimit = 36,
    [int]$Limit = 0,
    [int]$TimeoutSeconds = 120,
    [int]$MinimizeSteps = 1000,
    [switch]$OnlyFailed,
    [switch]$OnlyTimeouts,
    [switch]$NoTimeout,
    [switch]$RecoveryMode,
    [switch]$Force,
    [string]$SummaryName = 'summary.csv',
    [string]$InputSdf,
    [string]$OutputRoot,
    [string]$OpenBabelPath = 'obabel',
    [string]$OpenBabelDataDir
)

$ErrorActionPreference = 'Stop'

$root = (Get-Location).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $root 'ligand_data' }
if ([string]::IsNullOrWhiteSpace($InputSdf)) { $InputSdf = Join-Path $OutputRoot 'input.sdf' }
if ([string]::IsNullOrWhiteSpace($OpenBabelDataDir)) { $OpenBabelDataDir = Join-Path $root 'openbabel_data' }
$inputSdf = [System.IO.Path]::GetFullPath($InputSdf)
$ligandRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$preparedDir = Join-Path $ligandRoot 'prepared_sdf'
$pdbqtDir = Join-Path $ligandRoot 'pdbqt'
$logsDir = Join-Path $ligandRoot 'logs'
$failedDir = Join-Path $ligandRoot 'failed'
$summaryPath = Join-Path $ligandRoot $SummaryName
$obabel = $OpenBabelPath
$dataDir = [System.IO.Path]::GetFullPath($OpenBabelDataDir)

foreach ($dir in @($preparedDir, $pdbqtDir, $logsDir, $failedDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

if (!(Test-Path -LiteralPath $inputSdf)) { throw "Input SDF not found: $inputSdf" }
if (!(Test-Path -LiteralPath $obabel)) {
    $obabelCommand = Get-Command $obabel -ErrorAction SilentlyContinue
    if ($obabelCommand) { $obabel = $obabelCommand.Source } else { throw "Open Babel not found: $obabel" }
}
if (!(Test-Path -LiteralPath (Join-Path $dataDir 'mmff94s.ff'))) { throw "Open Babel data directory is incomplete: $dataDir" }

$env:BABEL_DATADIR = $dataDir
$env:OMP_NUM_THREADS = '1'
$env:MKL_NUM_THREADS = '1'

$ffText = (& $obabel -L forcefields 2>&1 | Out-String)
$forceFields = @('MMFF94s', 'MMFF94', 'UFF') | Where-Object {
    $ffText -match "(?m)^$($_)\s"
}
if ($forceFields.Count -eq 0) { throw 'No supported Open Babel force field was found.' }
$forceField = $forceFields[0]
$recoveryForceFields = @('MMFF94s', 'UFF') | Where-Object {
    $ffText -match "(?m)^$($_)\s"
}

$raw = [System.IO.File]::ReadAllText($inputSdf)
$blocks = [regex]::Split($raw, '(?m)^\$\$\$\$\r?\n') |
    Where-Object { $_.Trim().Length -gt 0 }

$records = @()
$recordIndex = 0
foreach ($block in $blocks) {
    $recordIndex++
    $normalizedBlock = $block -replace '(?m)^(\s*)(\d{3})(\d{3})(\s+.*V2000\s*)$', '$1$2 $3$4'
    $repairedCounts = ($normalizedBlock -ne $block)
    $block = $normalizedBlock
    $countsLine = ($block -split '\r?\n' | Where-Object { $_ -match 'V2000' } | Select-Object -First 1)
    $inputAtomCount = 9999
    if ($countsLine -match '^\s*(\d+)\s+(\d+)') { $inputAtomCount = [int]$Matches[1] }
    $recordTimeout = if ($NoTimeout) { 0 } elseif ($inputAtomCount -le 50) { $TimeoutSeconds } elseif ($inputAtomCount -le 100) { $TimeoutSeconds * 2 } else { $TimeoutSeconds * 3 }
    $id = $null
    foreach ($tag in @('CdId', 'ID', 'Name')) {
        $m = [regex]::Match($block, "(?ms)^>\s*<$tag>\s*\r?\n([^\r\n]*)")
        if ($m.Success -and $m.Groups[1].Value.Trim()) {
            $id = $m.Groups[1].Value.Trim()
            break
        }
    }
    if (!$id) { $id = "ligand_$recordIndex" }
    $safeId = [regex]::Replace($id, '[^\p{L}\p{Nd}_\.-]', '_')
    if ($safeId.Length -gt 100) { $safeId = $safeId.Substring(0, 100) }
    $base = ('{0:D5}_{1}' -f $recordIndex, $safeId)
    $records += [pscustomobject]@{
        Index = $recordIndex
        OriginalId = $id
        Base = $base
        RepairedCounts = $repairedCounts
        TimeoutSeconds = $recordTimeout
        Block = ($block.TrimEnd() + "`r`n" + '$$$$' + "`r`n")
    }
}

if ($Limit -gt 0) { $records = @($records | Select-Object -First $Limit) }
if ($OnlyTimeouts -or $OnlyFailed) {
    $existingSummary = Join-Path $ligandRoot 'summary.csv'
    if (!(Test-Path -LiteralPath $existingSummary)) { throw "Cannot use -OnlyFailed without $existingSummary" }
    $failedSet = @{}
    $summaryRows = Import-Csv -LiteralPath $existingSummary
    if ($OnlyTimeouts) {
        $summaryRows = $summaryRows | Where-Object { $_.Status -eq 'failed' -and $_.Error -match 'TIMEOUT' }
    } else {
        $summaryRows = $summaryRows | Where-Object { $_.Status -eq 'failed' }
    }
    foreach ($row in $summaryRows) {
        $failedSet[[int]$row.Index] = $true
    }
    $records = @($records | Where-Object { $failedSet.ContainsKey($_.Index) })
}

$results = $records | ForEach-Object -Parallel {
    $rec = $_
    $obabelPath = $using:obabel
    $steps = [string]$using:MinimizeSteps
    function Invoke-ObabelWithTimeout {
        param([string[]]$Arguments, [int]$TimeoutMs)
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $obabelPath
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        foreach ($arg in $Arguments) { [void]$psi.ArgumentList.Add([string]$arg) }
        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        [void]$proc.Start()
        if ($TimeoutMs -gt 0) {
            if (!$proc.WaitForExit($TimeoutMs)) {
                try { $proc.Kill($true) } catch {}
                return [pscustomobject]@{ ExitCode = -2; Output = 'TIMEOUT'; TimedOut = $true }
            }
        } else {
            $proc.WaitForExit()
        }
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        return [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = ($stdout + "`n" + $stderr); TimedOut = $false }
    }
    function Test-NonzeroCoordinates {
        param([string]$Text)
        foreach ($atomLine in ($Text -split '\r?\n')) {
            if ($atomLine -match '^\s*[+-]?\d+\.\d+\s+[+-]?\d+\.\d+\s+[+-]?\d+\.\d+\s+[A-Z]') {
                $parts = $atomLine.Trim() -split '\s+'
                if ([math]::Abs([double]$parts[0]) -gt 1e-6 -or [math]::Abs([double]$parts[1]) -gt 1e-6 -or [math]::Abs([double]$parts[2]) -gt 1e-6) { return $true }
            }
        }
        return $false
    }
    $tmpBase = Join-Path $env:TEMP ("mce_" + [guid]::NewGuid().ToString('N'))
    $tmpIn = "$tmpBase.sdf"
    $tmp3d = "$tmpBase.3d.sdf"
    $tmpPrepared = "$tmpBase.prepared.sdf"
    $prepared = Join-Path $using:preparedDir ($rec.Base + '.sdf')
    $pdbqt = Join-Path $using:pdbqtDir ($rec.Base + '.pdbqt')
    $log = Join-Path $using:logsDir ($rec.Base + '.log')
    $failed = Join-Path $using:failedDir ($rec.Base + '.sdf')
    $started = Get-Date

    try {
        $existingValid = $false
        $existingCoordinatesValid = $false
        $existingPreparedNeedsRepair = $false
        if (Test-Path -LiteralPath $prepared) {
            $preparedHeader = (Select-String -LiteralPath $prepared -Pattern 'V2000' | Select-Object -First 1).Line
            if ($preparedHeader -match '^\s*\d{6}\s+.*V2000\s*$') { $existingPreparedNeedsRepair = $true }
        }
        if (Test-Path -LiteralPath $pdbqt) {
            $existingText = Get-Content -LiteralPath $pdbqt -Raw -ErrorAction SilentlyContinue
            $existingAtomLines = @($existingText -split '\r?\n' | Where-Object { $_ -match '^(ATOM|HETATM)' })
            foreach ($existingAtomLine in $existingAtomLines) {
                $existingParts = $existingAtomLine.Trim() -split '\s+'
                if ($existingParts.Count -ge 8 -and ([math]::Abs([double]$existingParts[5]) -gt 1e-6 -or [math]::Abs([double]$existingParts[6]) -gt 1e-6 -or [math]::Abs([double]$existingParts[7]) -gt 1e-6)) {
                    $existingCoordinatesValid = $true
                    break
                }
            }
            $existingValid = ($existingAtomLines.Count -gt 0) -and ($existingText -match '(?m)^TORSDOF\s+') -and $existingCoordinatesValid
        }
        if (!$using:Force -and !$rec.RepairedCounts -and !$existingPreparedNeedsRepair -and $existingValid) {
            return [pscustomobject]@{
                Index=$rec.Index; OriginalId=$rec.OriginalId; File=$rec.Base; Status='skipped_existing'
                ForceField=$using:forceField; RepairedCounts=$rec.RepairedCounts; TimeoutSeconds=$rec.TimeoutSeconds; AtomCount=''; TotalCharge=''; Error=''; Seconds=0
            }
        }

        [System.IO.File]::WriteAllText($tmpIn, $rec.Block, [System.Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $prepared) { Remove-Item -LiteralPath $prepared -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $pdbqt) { Remove-Item -LiteralPath $pdbqt -Force -ErrorAction SilentlyContinue }

        $usedForceField = $null
        $minimizationLogs = New-Object System.Collections.Generic.List[string]
        $minInput = $tmpIn
        $candidateForceFields = if ($using:RecoveryMode) { $using:recoveryForceFields } else { $using:forceFields }
        if ($using:RecoveryMode) {
            $runGen = Invoke-ObabelWithTimeout -Arguments @('-isdf', $tmpIn, '-osdf', '-O', $tmp3d, '-p', '7.4', '--gen3d') -TimeoutMs ($rec.TimeoutSeconds * 1000)
            [void]$minimizationLogs.Add('[3D generation] ' + $runGen.Output)
            if ($runGen.ExitCode -ne 0 -or !(Test-Path -LiteralPath $tmp3d) -or ((Get-Item $tmp3d).Length -eq 0)) { throw "3D generation failed: $($runGen.Output)" }
            $generated3dText = [System.IO.File]::ReadAllText($tmp3d)
            if (!(Test-NonzeroCoordinates $generated3dText)) { throw '3D generation produced all-zero coordinates' }
            $minInput = $tmp3d
        }
        foreach ($candidateForceField in $candidateForceFields) {
            if (Test-Path -LiteralPath $tmpPrepared) { Remove-Item -LiteralPath $tmpPrepared -Force -ErrorAction SilentlyContinue }
            if ($using:RecoveryMode) {
                $runArgs = @('-isdf', $minInput, '-osdf', '-O', $tmpPrepared, '--minimize', '--ff', $candidateForceField, '--steps', $steps)
            } else {
                $runArgs = @('-isdf', $tmpIn, '-osdf', '-O', $tmpPrepared, '-p', '7.4', '--gen3d', '--minimize', '--ff', $candidateForceField, '--steps', $steps)
            }
            $run1 = Invoke-ObabelWithTimeout -Arguments $runArgs -TimeoutMs ($rec.TimeoutSeconds * 1000)
            $attemptLog = $run1.Output
            $code1 = $run1.ExitCode
            [void]$minimizationLogs.Add("[$candidateForceField] $attemptLog")
            if ($code1 -eq 0 -and (Test-Path -LiteralPath $tmpPrepared) -and ((Get-Item $tmpPrepared).Length -gt 0)) {
                $candidatePreparedText = [System.IO.File]::ReadAllText($tmpPrepared)
                $candidateNormalizedText = $candidatePreparedText -replace '(?m)^(\s*)(\d{3})(\d{3})(\s+.*V2000\s*)$', '$1$2 $3$4'
                if ($candidateNormalizedText -ne $candidatePreparedText) {
                    [System.IO.File]::WriteAllText($tmpPrepared, $candidateNormalizedText, [System.Text.UTF8Encoding]::new($false))
                    $candidatePreparedText = $candidateNormalizedText
                    [void]$minimizationLogs.Add("[$candidateForceField] SDF counts normalized")
                }
                $nonzeroCoordinate = Test-NonzeroCoordinates $candidatePreparedText
                if ($nonzeroCoordinate) {
                    $usedForceField = $candidateForceField
                    break
                }
                [void]$minimizationLogs.Add("[$candidateForceField] rejected: all 3D coordinates are zero")
            }
        }
        if (!$usedForceField) {
            throw "3D/minimization failed for all force fields: $($minimizationLogs -join [Environment]::NewLine)"
        }

        $preparedText = [System.IO.File]::ReadAllText($tmpPrepared)
        $normalizedPreparedText = $preparedText -replace '(?m)^(\s*)(\d{3})(\d{3})(\s+.*V2000\s*)$', '$1$2 $3$4'
        if ($normalizedPreparedText -ne $preparedText) {
            [System.IO.File]::WriteAllText($tmpPrepared, $normalizedPreparedText, [System.Text.UTF8Encoding]::new($false))
            [void]$minimizationLogs.Add('[SDF counts normalized after Open Babel output]')
        }
        Copy-Item -LiteralPath $tmpPrepared -Destination $prepared -Force
        $conversionTimeout = if ($using:NoTimeout) { 0 } else { $using:TimeoutSeconds * 1000 }
        $run2 = Invoke-ObabelWithTimeout -Arguments @('-isdf', $tmpPrepared, '-opdbqt', '-O', $pdbqt, '--partialcharge', 'gasteiger') -TimeoutMs $conversionTimeout
        $log2 = $run2.Output
        $code2 = $run2.ExitCode
        if ($code2 -ne 0 -or !(Test-Path -LiteralPath $pdbqt) -or ((Get-Item $pdbqt).Length -eq 0)) {
            throw "PDBQT conversion failed (exit $code2): $log2"
        }

        $pdbLines = Get-Content -LiteralPath $pdbqt
        $atomLines = @($pdbLines | Where-Object { $_ -match '^(ATOM|HETATM)' })
        if ($atomLines.Count -eq 0 -or !($pdbLines -match '^TORSDOF\s+')) {
            throw 'PDBQT validation failed: missing atom records or TORSDOF.'
        }
        $charges = foreach ($line in $atomLines) {
            $cm = [regex]::Match($line, '\s([+-]?\d+(?:\.\d+)?)\s+\S\s*$')
            if ($cm.Success) { [double]$cm.Groups[1].Value }
        }
        $totalCharge = if ($charges.Count) { [math]::Round((($charges | Measure-Object -Sum).Sum), 3) } else { '' }
        $allLog = (($minimizationLogs -join [Environment]::NewLine) + $log2).Trim()
        [System.IO.File]::WriteAllText($log, $allLog)
        if (Test-Path -LiteralPath $failed) { Remove-Item -LiteralPath $failed -Force -ErrorAction SilentlyContinue }
        [pscustomobject]@{
            Index=$rec.Index; OriginalId=$rec.OriginalId; File=$rec.Base; Status='success'
            ForceField=$usedForceField; RepairedCounts=$rec.RepairedCounts; TimeoutSeconds=$rec.TimeoutSeconds; AtomCount=$atomLines.Count; TotalCharge=$totalCharge; Error=''
            Seconds=[math]::Round(((Get-Date)-$started).TotalSeconds, 2)
        }
    }
    catch {
        try { [System.IO.File]::WriteAllText($log, $_.Exception.Message) } catch {}
        try { [System.IO.File]::WriteAllText($failed, $rec.Block, [System.Text.UTF8Encoding]::new($false)) } catch {}
        [pscustomobject]@{
            Index=$rec.Index; OriginalId=$rec.OriginalId; File=$rec.Base; Status='failed'
            ForceField=$using:forceField; RepairedCounts=$rec.RepairedCounts; TimeoutSeconds=$rec.TimeoutSeconds; AtomCount=''; TotalCharge=''; Error=$_.Exception.Message
            Seconds=[math]::Round(((Get-Date)-$started).TotalSeconds, 2)
        }
    }
    finally {
        Remove-Item -LiteralPath $tmpIn, $tmp3d, $tmpPrepared -Force -ErrorAction SilentlyContinue
    }
} -ThrottleLimit $ThrottleLimit

$results | Sort-Object Index | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$ok = @($results | Where-Object { $_.Status -eq 'success' }).Count
$skipped = @($results | Where-Object { $_.Status -eq 'skipped_existing' }).Count
$failedCount = @($results | Where-Object { $_.Status -eq 'failed' }).Count
Write-Output "Input records: $($records.Count)"
Write-Output "Force field: $forceField"
Write-Output "Workers: $ThrottleLimit"
Write-Output "Success: $ok; skipped: $skipped; failed: $failedCount"
Write-Output "Summary: $summaryPath"

