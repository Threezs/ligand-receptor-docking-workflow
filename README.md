# Ligand–receptor docking workflow

This repository records the reusable processing steps and scripts used for the SPP1 ligand–receptor docking run. It covers:

1. receptor preparation from an AlphaFold/CIF model;
2. ligand SDF repair, 3D generation, minimization and PDBQT conversion with Open Babel;
3. AutoDock Vina box configuration and batch docking;
4. pose parsing, affinity summarization and cleanup of stale intermediate files.

The repository intentionally contains source code, configuration templates and QC notes only. The original ligand library, generated structures, docking poses, model files, logs and installer binaries remain outside Git because they are large, run-specific or subject to separate data/software terms.

## Repository layout

- `scripts/prepare_receptor_kollman.py` — AutoDockTools receptor preparation with Kollman charges.
- `scripts/prepare_ligands.ps1` — parallel ligand preparation with timeout, force-field fallback, coordinate/PDBQT validation and resumable failure recovery.
- `scripts/cleanup_historical.ps1` — remove stale ligand outputs while preserving successful records.
- `scripts/summarize_after_vina.ps1` — collect the best Vina affinity from completed pose files.
- `scripts/summarize_after_parallel.ps1` — same summary step after several worker processes finish.
- `configs/` — Vina box and batch templates used for the SPP1 RGD-site run.
- `docs/` — receptor QC report and the end-to-end procedure.

## Requirements

- Windows PowerShell 7 or later.
- Open Babel 3.1.x (`obabel`) with its data directory available through `BABEL_DATADIR`.
- AutoDockTools/MGLTools for `AD4ReceptorPreparation`.
- AutoDock Vina 1.2.x for docking.
- Python with the AutoDockTools/MolKit modules for `prepare_receptor_kollman.py`.

## Quick start

Run commands from the repository root. The paths below are examples and should point to your local input/output directories.

```powershell
# 1. Prepare the receptor
python scripts/prepare_receptor_kollman.py `
  path\to\SPP1_2_model2_mature.pdb `
  path\to\receptor_processed\SPP1_2_model2_rigid.pdbqt

# 2. Prepare ligands (the input SDF is not part of this repository)
./scripts/prepare_ligands.ps1 `
  -InputSdf path\to\ligands.sdf `
  -OutputRoot path\to\ligand_data `
  -OpenBabelPath obabel `
  -OpenBabelDataDir path\to\openbabel_data `
  -ThrottleLimit 36 -MinimizeSteps 1000

# 3. Run Vina using configs/vina_config_cpu16.txt after replacing the receptor path.
vina --config configs/vina_config_cpu16.txt --ligand path\to\ligand.pdbqt --out path\to\pose.pdbqt

# 4. Summarize completed poses
./scripts/summarize_after_vina.ps1 `
  -PosesDir path\to\docking_results\poses `
  -OutputCsv path\to\docking_results\best_affinity.csv
```

Use `-OnlyFailed`, `-OnlyTimeouts` or `-RecoveryMode` on the ligand script to resume a previous run. Keep the generated `summary.csv` as the run manifest.

## Reproducibility notes

The recorded SPP1 run used mature SPP1 chain A and a 30 Å cube centered at `(-17.2, -52.6, 19.8)` around the RGD159–161 functional site. This is a functional-site docking box for comparability across ligands; it is not a claim that SPP1 has a resolved small-molecule pocket. See `configs/pocket_definition.txt` and `docs/WORKFLOW.md` for the exact rationale and QC checkpoints.

