#!/usr/bin/env bash
#==============================================================================
# SLURM Dorado Basecalling + Demultiplexing Script (ZONDER modbase)
# Project  : NGS-26-EQ
# Sample   : various
# Platform : PromethION 2i (P2i)
# Model    : SUP v5.2.0 (expliciet gepind)
# Dorado   : v2.1.1 (release 19-02-2026, ONT)
# Env      : basecall-qc (mamba; samtools/cramino/nanoplot voor QC)
# Auteur   : harde004 (frank.harders@wur.nl)
# Datum    : 2026-08-07
#==============================================================================

#-----------------------------Mail-instellingen--------------------------------
#SBATCH --mail-user=frank.harders@wur.nl
#SBATCH --mail-type=FAIL,END

#-----------------------------Output / error logs------------------------------
#SBATCH --output=/lustre/scratch/WUR/WBVR/harde004/NGS-26-EQ/NGS-26-EQ-1/20260730_1322_P2I-00116-A_PBM40282_b639ac1a/dorado-output_%j.txt
#SBATCH --error=/lustre/scratch/WUR/WBVR/harde004/NGS-26-EQ/NGS-26-EQ-1/20260730_1322_P2I-00116-A_PBM40282_b639ac1a/dorado-error_%j.txt

#-----------------------------Job-informatie-----------------------------------
#SBATCH --job-name=VetB-demux-GPU
#SBATCH --comment=1600002507

#-----------------------------Resources----------------------------------------
#SBATCH --time=2-0:0:0
#SBATCH --nodes=1
#SBATCH --cpus-per-task=28
#SBATCH --mem=256G
#SBATCH --partition=gpu
#SBATCH --gres=gpu:2
#SBATCH --constraint=A100

#==============================================================================
# Configuratie
#==============================================================================

set -euo pipefail
shopt -s nullglob

SCRIPT_NAME="01b_dorado_basecall.sh"
SCRIPT_VERSION="2.2.0"

## Project ID (voor billing / terugvinden data)
NGS_PROJECT="NGS-26-EQ"

## Paden
FLOWCELL_DIR=/lustre/scratch/WUR/WBVR/harde004/NGS-26-EQ/NGS-26-EQ-1/20260730_1322_P2I-00116-A_PBM40282_b639ac1a
IN_DIR="${FLOWCELL_DIR}/pod5"
OUT_DIR="${FLOWCELL_DIR}/01_basecalled"
OUT_BAM="${OUT_DIR}/calls.sup.bam"

## Dorado binary (standalone, bewust buiten de env)
DORADO=/home/WUR/harde004/GIT/dorado-2.1.1-linux-x64/bin/dorado

## Mamba env (QC-tooling); auto-detectie over bekende roots (volledige prefix)
ENV_PREFIX=""
for p in "${HOME}/miniconda3/envs/basecall-qc" \
         "${HOME}/.local/share/mamba/envs/basecall-qc"; do
    [[ -d "$p" ]] && ENV_PREFIX="$p" && break
done

## Basecalling-parameters — model EXPLICIET gepind.
## NB: er bestaat geen sup@v6.0 — v6.0 is HAC-only.
MODEL_SPEC="sup@v5.2.0"
KIT=SQK-NBD114-96

## Provenance-bestand (machine-leesbaar, voor M&M / supplementary)
mkdir -p "${OUT_DIR}"
PROVENANCE="${OUT_DIR}/provenance_${SLURM_JOB_ID:-manual}_$(date +%Y%m%d).txt"

log() {
    local msg="[$(date -Is)] $*"
    echo "${msg}" >&2
    echo "${msg}" >> "${PROVENANCE}"
}

trap 'rc=$?; log "=== Job beeindigd, exit code: ${rc} ==="; exit ${rc}' EXIT

#==============================================================================
# Mamba env activeren (PATH-prepend: robuust in non-interactieve SLURM jobs)
#==============================================================================

if [[ -z "${ENV_PREFIX}" ]]; then
    log "FOUT: mamba env 'basecall-qc' niet gevonden (gecheckt: miniconda3 en .local/share/mamba)"
    exit 1
fi
export PATH="${ENV_PREFIX}/bin:${PATH}"

if [[ "$(command -v samtools)" != "${ENV_PREFIX}/bin/samtools" ]]; then
    log "FOUT: samtools resolvet niet naar de basecall-qc env."
    exit 1
fi

#==============================================================================
# Provenance-logging: software, hardware, omgeving
#==============================================================================

log "=== Dorado basecalling gestart ==="
log "Script          : ${SCRIPT_NAME} v${SCRIPT_VERSION}"
log "Project         : ${NGS_PROJECT}"
log "Flowcell-dir    : ${FLOWCELL_DIR}"
log "Input           : ${IN_DIR}"
log "Output BAM      : ${OUT_BAM}"
log "Provenance      : ${PROVENANCE}"

## --- Job / cluster context ---
log "Hostname        : $(hostname -f 2>/dev/null || hostname)"
log "SLURM job ID    : ${SLURM_JOB_ID:-n.v.t. (interactief)}"
log "SLURM nodelist  : ${SLURM_JOB_NODELIST:-n.v.t.}"
log "SLURM partition : ${SLURM_JOB_PARTITION:-n.v.t.}"
log "CPUs / mem      : ${SLURM_CPUS_PER_TASK:-?} cpus, ${SLURM_MEM_PER_NODE:-?} MB"

## --- OS / kernel ---
log "OS              : $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME}" || echo 'onbekend')"
log "Kernel          : $(uname -r)"

## --- GPU / driver / CUDA ---
log "GPUs            : $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd, || echo 'onbekend')"
log "NVIDIA driver   : $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo 'onbekend')"
log "CUDA (driver)   : $(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version: \K[0-9.]+' | head -1 || echo 'onbekend')"

## --- Dorado ---
log "Dorado binary   : ${DORADO}"
log "Dorado versie   : $(${DORADO} --version 2>&1 | head -1)"
log "Dorado sha256   : $(sha256sum "${DORADO}" | cut -d' ' -f1)"

## --- Env-tooling (versies uit basecall-qc) ---
log "Mamba env       : ${ENV_PREFIX}"
log "samtools        : $(samtools --version | head -1)"
log "cramino         : $(cramino --version 2>&1 | head -1 || echo 'niet gevonden')"

## --- Parameters (exact zoals gebruikt; kopieerbaar naar M&M) ---
log "Model-spec      : ${MODEL_SPEC}"
log "Barcode-kit     : ${KIT}"
log "Demux-modus     : --barcode-both-ends (barcode 5' EN 3' vereist)"
log "Emit-moves      : aan (mv:B/ts-tags per read; nodig voor signal-level analyse, grotere BAM)"

#==============================================================================
# Validatie voor de start
#==============================================================================

POD5_COUNT=$(find "${IN_DIR}" -name "*.pod5" | wc -l)
if [[ "${POD5_COUNT}" -eq 0 ]]; then
    log "FOUT: geen .pod5 bestanden gevonden in ${IN_DIR}"
    exit 1
fi
POD5_SIZE=$(du -sh "${IN_DIR}" | cut -f1)
log "POD5-bestanden  : ${POD5_COUNT} (totaal ${POD5_SIZE})"

#==============================================================================
# Dorado basecalling + barcode-classificatie
#==============================================================================

CMD=("${DORADO}" basecaller
     --device cuda:all
     --barcode-both-ends
     --emit-moves
     --kit-name "${KIT}"
     "${MODEL_SPEC}"
     "${IN_DIR}")

log "Commando        : ${CMD[*]} > ${OUT_BAM}"

"${CMD[@]}" > "${OUT_BAM}"

log "Dorado succesvol afgerond."

#==============================================================================
# Post-run provenance + eerste QC
#==============================================================================

log "--- BAM @RG header (basecall model) ---"
samtools view -H "${OUT_BAM}" \
    | grep -m1 '^@RG' \
    | tr '\t' '\n' \
    | grep -E 'basecall_model|runid|PU|PM|DT' \
    | while IFS= read -r line; do log "  ${line}"; done

log "--- Tag-check (eerste read: moves aanwezig?) ---"
FIRST_TAGS=$( (samtools view "${OUT_BAM}" || true) | head -n1 | tr '\t' '\n' \
    | grep -oE '^(mv|ts|BC):' | sort -u | paste -sd, )
log "  Tags gevonden : ${FIRST_TAGS:-GEEN}"
if [[ ",${FIRST_TAGS}," != *",mv:,"* ]]; then
    log "  WAARSCHUWING: mv-tag ontbreekt in eerste read!"
fi

log "--- cramino (yield / N50 / Q-score) ---"
cramino "${OUT_BAM}" 2>&1 | while IFS= read -r line; do log "  ${line}"; done

log "--- Reads per barcode (BC-tag) ---"
samtools view "${OUT_BAM}" \
    | grep -oP 'BC:Z:\K\S+' \
    | sort | uniq -c | sort -rn \
    | while IFS= read -r line; do log "  ${line}"; done

log "Schijfgebruik output: $(du -sh "${OUT_DIR}" | cut -f1)"
log "=== Job voltooid ==="
