#!/bin/bash
# Batch runner for compare_vcf.sh across subdirectories
set -euo pipefail

# -------- User configuration --------
# Update these paths to your local reference files/binaries
export SCRIPT_DIR="${SCRIPT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export SNPSIFT_BIN="${SNPSIFT_BIN:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/snpEff/SnpSift.jar}"
export HAPLOCHECK_BIN="${HAPLOCHECK_BIN:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/haplocheck/haplocheck.jar}"
export ANN_GNOMAD="${ANN_GNOMAD:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/gnomAD/gnomad.genomes.v3.1.sites.chrM.vcf}"
export ANN_MITOMAP_DISEASE="${ANN_MITOMAP_DISEASE:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/disease-nosp.vcf}"
export ANN_MITOMAP_POLYMORPHISMS="${ANN_MITOMAP_POLYMORPHISMS:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/polymorphisms.vcf}"

# Base directory containing comparison folders
BASE_DIR="${1:-/Users/marcferre/Documents/Recherche/Projets/Nanomito/Analyses/Comparaisons/2025-01 Article/Anonymized}"

# -------- Helpers --------
COMPARE_SCRIPT="$SCRIPT_DIR/tools/compare_vcf.sh"

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "[ERROR] Missing $label: $path" >&2
    exit 1
  fi
}

check_refs() {
  require_file "$SNPSIFT_BIN" "SNPSIFT_BIN"
  require_file "$ANN_GNOMAD" "ANN_GNOMAD"
  require_file "$ANN_MITOMAP_DISEASE" "ANN_MITOMAP_DISEASE"
  require_file "$ANN_MITOMAP_POLYMORPHISMS" "ANN_MITOMAP_POLYMORPHISMS"
  require_file "$HAPLOCHECK_BIN" "HAPLOCHECK_BIN"
}

run_one() {
  local dir="$1"
  echo "[INFO] Processing: $dir"
  if [[ ! -d "$dir" ]]; then
    echo "[WARN] Skip (not a directory): $dir" >&2
    return
  fi
  # Quick presence check for expected VCFs
  local nano
  local illum
  nano=$(find "$dir" -maxdepth 1 -name "*.ann.vcf" -print -quit)
  illum=$(find "$dir" -maxdepth 1 -name "i---*.vcf" -print -quit)
  if [[ -z "$nano" || -z "$illum" ]]; then
    echo "[WARN] Skip (missing .ann.vcf or i---*.vcf): $dir" >&2
    return
  fi
  if ! bash "$COMPARE_SCRIPT" "$dir"; then
    echo "[ERROR] compare_vcf failed for: $dir" >&2
    return 1
  fi
}

main() {
  if [[ ! -d "$BASE_DIR" ]]; then
    echo "[ERROR] Base directory not found: $BASE_DIR" >&2
    exit 1
  fi
  check_refs
  echo "[INFO] Starting batch in: $BASE_DIR"
  local status=0
  while IFS= read -r subdir; do
    run_one "$subdir" || status=1
  done < <(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  echo "[INFO] Batch done. Status=$status"
  exit "$status"
}

main "$@"
