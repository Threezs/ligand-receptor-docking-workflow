# Processing procedure

## 1. Receptor

1. Select the SPP1 model and retain the mature protein (UniProt residues 17–314, chain A).
2. Convert the selected CIF model to a PDB while preserving residue numbering and pLDDT values in the B-factor column.
3. Run `scripts/prepare_receptor_kollman.py` with AutoDockTools. The preparation repairs bonds/hydrogens, adds Kollman charges, removes waters/non-standard residues and writes a rigid receptor PDBQT.
4. Check atom/residue counts, chain identity, explicit hydrogens, atom types and total charge against `docs/receptor_processing_report.txt`.

## 2. Ligands

`prepare_ligands.ps1` reads an SDF record by record. For each record it:

- repairs malformed V2000 counts lines;
- derives a stable five-digit filename from `CdId`, `ID` or `Name`;
- chooses a timeout from input atom count;
- generates 3D coordinates and minimizes with MMFF94s/MMFF94/UFF fallback;
- rejects all-zero coordinates;
- converts the result to PDBQT with Gasteiger partial charges;
- validates atom records, `TORSDOF`, non-zero coordinates and total charge;
- writes `summary.csv`, per-ligand logs and failed SDF copies;
- skips valid existing outputs unless `-Force` is supplied.

For timed-out or failed records, rerun with `-OnlyTimeouts`, `-OnlyFailed` or `-RecoveryMode`. The latter performs an explicit 3D generation pass before minimization.

## 3. Docking

Use the same receptor and box for all ligands. Replace the receptor path in `configs/vina_config_cpu16.txt` and choose a CPU count appropriate for the host. A batch configuration is included in `configs/batch.conf`. Keep each run's input manifest and Vina logs with the run outputs.

## 4. Summarization and cleanup

After Vina workers finish, run one of the summary scripts to extract `REMARK VINA RESULT` values and sort by affinity. `cleanup_historical.ps1` uses the ligand summary manifest to remove stale PDBQT/SDF/log files while retaining successful and skipped-existing records.

## 5. Validation gates

Before interpreting scores, confirm:

- every selected ligand has a non-empty PDBQT with atom records and `TORSDOF`;
- no ligand has all-zero coordinates;
- receptor and ligand paths in the Vina config resolve to the intended files;
- the docking box is identical across the comparison set;
- failed/time-out records are excluded or explicitly recovered;
- affinity summaries are generated only from completed pose files.

