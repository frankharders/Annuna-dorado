# Dorado basecalling (PromethION 2i, SLURM)

SLURM scripts for Oxford Nanopore basecalling + barcode classification with
[Dorado](https://github.com/nanoporetech/dorado), with full provenance logging
for reproducibility (M&M-ready).

## Versions

| Component | Version |
|---|---|
| Scripts | v2.3.0 |
| Dorado | v2.1.1 (standalone binary, **not** in the conda env) |
| Simplex model | `dna_r10.4.1_e8.2_400bps_sup@v5.2.0` (explicitly pinned; no sup exists for v6.0) |
| Modbase models | `6mA@v1`, `4mC_5mC@v1` (01a only) |
| Barcode kit | SQK-NBD114-96, `--barcode-both-ends` |
| Moves table | `--emit-moves` (both scripts): per-read `mv:B`/`ts` tags for signal-level analysis |
| QC env | `basecall-qc` (samtools ≥1.21, ont-modkit ≥0.6, cramino, NanoPlot, nanoq, seqkit, pod5, MultiQC) |

## Files

| File | Purpose |
|---|---|
| `01a_dorado_basecall_mod.sh` | SUP basecalling **with** modified bases (6mA + 4mC/5mC) |
| `01b_dorado_basecall.sh` | SUP basecalling **without** modified bases |
| `env_basecall_qc.yml` | Mamba env spec for QC tooling |

## Setup

```bash
mamba env create -f env_basecall_qc.yml
```

The env spec uses `nodefaults`; if the solve hangs, remove the Anaconda
`defaults` channel and set `channel_priority: strict` in your `~/.condarc`.
Dorado is expected as a standalone binary (path set via `DORADO` in the
scripts).

## Usage

The scripts are **portable per flowcell**: `FLOWCELL_DIR` is derived from the
directory you submit from (`SLURM_SUBMIT_DIR`), and SLURM logs are written
there too. Copy the script into the flowcell directory (or keep one central
copy) and submit **from within the flowcell directory**:

```bash
cd /path/to/<FLOWCELL_DIR>       # must contain pod5/
sbatch 01a_dorado_basecall_mod.sh   # or 01b
```

No per-flowcell path editing needed. One-time settings in the config block:
`NGS_PROJECT`, `KIT`, `DORADO`, SBATCH mail address. The script aborts
cleanly if the submit directory contains no `pod5/`.

## Input

```
<FLOWCELL_DIR>/
└── pod5/                  # raw .pod5 files (MinKNOW output)
```

## Output

```
<FLOWCELL_DIR>/
├── 01_basecalled/
│   ├── calls.sup.mod.bam                    # 01a (MM/ML tags, BC tag per read)
│   ├── calls.sup.bam                        # 01b
│   └── provenance_[mod_]<jobid>_<date>.txt  # versions, models, QC — see below
├── dorado-[mod-]output_<jobid>.txt          # SLURM stdout log
└── dorado-[mod-]error_<jobid>.txt           # SLURM stderr log
```

Barcodes are classified in the BAM (`BC` tag); physical per-barcode splitting
is a separate downstream step (`dorado demux --no-classify`). With
`--emit-moves`, every read additionally carries the move table (`mv:B` +
`ts` tags), required for signal-level tools; expect a substantially larger
BAM (roughly +30–50%).

## Provenance file

Written per run, machine-readable, suitable as publication supplementary:

- script name/version, project, full command line
- host, SLURM job ID/nodelist/partition, OS, kernel
- GPU types, NVIDIA driver, CUDA version
- dorado version + sha256 of the binary; env tool versions
- **BAM `@RG` header** — the authoritative record of the models actually used
- first-pass QC: tag check (`mv`, and `MM`/`ML` in 01a — warns if missing),
  cramino (yield/N50/Q), `modkit summary` (01a), reads per barcode

## Notes

- Scripts are copy-safe per flowcell: no hardcoded flowcell paths (since
  v2.3.0); logs and output always land in/under the submit directory.
- Models are pinned explicitly so a future dorado release can never silently
  select a different model.
- Every script prints `SCRIPT_NAME` / `SCRIPT_VERSION` in its log header.
- Modbase calling (01a) is noticeably slower than plain SUP (01b).
