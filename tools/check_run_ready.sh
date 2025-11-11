#!/usr/bin/env bash
set -euo pipefail

# Quick pre-flight check for a Nanomito run directory
# Validates presence of key outputs needed by wf-finalize.sh
# Usage: tools/check_run_ready.sh [RUN_DIR=. ] [--strict]

usage() {
  echo "Usage: $0 [RUN_DIR] [--strict] [--json|--tsv]" >&2
  exit 1
}

RUN_DIR="${1:-.}"
STRICT="false"
FMT="text" # text|json|tsv
if [[ $# -ge 1 ]]; then
  for arg in "$@"; do
    case "$arg" in
      --strict) STRICT="true" ;;
      --json) FMT="json" ;;
      --tsv) FMT="tsv" ;;
      -h|--help) usage ;;
      *) RUN_DIR="$arg" ;;
    esac
  done
fi

# Normalize path
RUN_DIR="$(cd "$RUN_DIR" && pwd)"
RUN_ID="$(basename "$RUN_DIR")"
PROCESS_DIR="$RUN_DIR/processing"

PASS=0; WARN=0; FAIL=0
ITEMS=()
log_item() { ITEMS+=("$1	$2"); }
err() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); log_item "FAIL" "$1"; }
warn() { echo "[WARN] $1"; WARN=$((WARN+1)); log_item "WARN" "$1"; }
ok() { echo "[OK]   $1"; PASS=$((PASS+1)); log_item "OK" "$1"; }

echo "=========================================="
echo "  NANOMITO QUICK CHECK for $RUN_ID"
echo "=========================================="

test -d "$RUN_DIR" || { echo "Run directory not found: $RUN_DIR"; exit 2; }

# 1) Required base directories
if [[ -d "$PROCESS_DIR" ]]; then ok "processing/ present"; else err "processing/ missing ($PROCESS_DIR)"; fi

# 2) Summary files (helpful but not strictly required)
SUM_WF="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"
SUM_DEM="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
SUM_HAP="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"

[[ -f "$SUM_WF" ]] && ok "workflows_summary.$RUN_ID.tsv" || warn "workflows_summary.$RUN_ID.tsv missing"
[[ -f "$SUM_DEM" ]] && ok "demult_summary.$RUN_ID.tsv" || warn "demult_summary.$RUN_ID.tsv missing"
[[ -f "$SUM_HAP" ]] && ok "haplocheck_summary.$RUN_ID.tsv" || warn "haplocheck_summary.$RUN_ID.tsv missing"

# 3) Per-sample files
SAMPLES_FOUND=0
if [[ -d "$PROCESS_DIR" ]]; then
  shopt -s nullglob
  for sdir in "$PROCESS_DIR"/*/ ; do
    sname="$(basename "$sdir")"
    # Skip top-level slurm logs pseudo-sample directories if any (heuristic)
    if [[ "$sname" == slurm-* || "$sname" == "email-"* ]]; then continue; fi

    SAMPLES_FOUND=$((SAMPLES_FOUND+1))
    
    # Check for NO_DATA marker
    no_data_marker="$sdir/NO_DATA.marker"
    if [[ -f "$no_data_marker" ]]; then
      warn "${sname}: NO DATA (no reads matched both references - analysis skipped)"
      continue
    fi
    
    bam="$sdir/${sname}.chrM.sup,5mC_5hmC,6mA.sorted.bam"
    ann_vcf="$sdir/${sname}.ann.vcf"
    ann_tsv="$sdir/${sname}.ann.tsv"
    del="$sdir/varcall/${sname}.baldur_del.txt"

    [[ -f "$bam" ]] && ok "${sname}: BAM present" || err "${sname}: BAM missing (${bam})"
    [[ -f "$ann_vcf" ]] && ok "${sname}: ann.vcf present" || warn "${sname}: ann.vcf missing"
    [[ -f "$ann_tsv" ]] && ok "${sname}: ann.tsv present" || warn "${sname}: ann.tsv missing"
    [[ -f "$del" ]] && ok "${sname}: deletions present" || warn "${sname}: deletions (baldur_del.txt) missing"
  done
  shopt -u nullglob
fi

if (( SAMPLES_FOUND == 0 )); then warn "No sample directories found under processing/"; fi

# 4) Archiving summary (optional)
ARCH_SUM="$PROCESS_DIR/archiving_summary.$RUN_ID.tsv"
[[ -f "$ARCH_SUM" ]] && ok "archiving_summary.$RUN_ID.tsv" || warn "archiving_summary.$RUN_ID.tsv missing"

# 5) Final status
if [[ "$FMT" == "json" ]]; then
  # Build simple JSON
  printf '{"run_id":"%s","pass":%d,"warn":%d,"fail":%d,"items":[' "$RUN_ID" "$PASS" "$WARN" "$FAIL"
  first=1
  for it in "${ITEMS[@]}"; do
    level=${it%%$'\t'*}
    msg=${it#*$'\t'}
    # escape quotes and backslashes
    msg_esc=${msg//\\/\\\\}; msg_esc=${msg_esc//"/\\"}
    if (( first )); then first=0; else printf ','; fi
    printf '{"level":"%s","message":"%s"}' "$level" "$msg_esc"
  done
  printf ']}'
  printf '\n'
else
  if [[ "$FMT" == "tsv" ]]; then
    for it in "${ITEMS[@]}"; do
      printf "%s\n" "$it"
    done
  else
    echo "------------------------------------------"
    echo "Result: PASS=$PASS  WARN=$WARN  FAIL=$FAIL"
  fi
fi

if [[ "$STRICT" == "true" ]] && (( FAIL > 0 )); then
  [[ "$FMT" == "text" ]] && echo "Strict mode: failing due to missing required artifacts."
  exit 1
fi
exit 0
