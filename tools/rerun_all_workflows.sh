#!/usr/bin/env bash
# SPDX-License-Identifier: CECILL-2.1
# Batch re-run Nanomito workflows over a set of runs.
# Submits per run: submit_nanomito.sh --skip-bchg (default) to reprocess with latest annotations/AF.
#
# Usage:
#   tools/rerun_all_workflows.sh /path/to/runs_root [options]
#
# Options:
#   --dry-run           Print commands without executing
#   --no-skip-bchg      Do not pass --skip-bchg (also rerun bchg)
#   --only-needing      Submit only runs that appear to need rerun
#   --pattern GLOB      Only process directories matching the glob (e.g., 2405*)
#   --sleep SEC         Pause between submissions (default: 2s)
#   --include-unclassified  Forward to submit_nanomito.sh
#   --only-samples LIST      Forward to submit_nanomito.sh (e.g., S1,S2)
#   --export-name NAME       Forward to submit_nanomito.sh
#   --extra "ARGS"        Extra args forwarded to submit_nanomito.sh as-is
#   --summary FILE        Write a TSV summary (timestamp, run_dir, status, args)
#
# Notes:
# - "--only-needing": looks for a Nanopore *.ann.vcf (or .vcf.gz) and checks for INFO/AF header and prefixed MitoMap_/gnomAD_ tags. If missing → rerun.
# - You can adjust run discovery logic via --pattern.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUBMIT_SCRIPT="${SCRIPT_DIR}/submit_nanomito.sh"

if [[ ! -x "$SUBMIT_SCRIPT" ]]; then
  echo "[ERROR] Script not found or not executable: $SUBMIT_SCRIPT" >&2
  exit 1
fi

DRY_RUN=false
SKIP_BCHG=true
ONLY_NEED=false
PATTERN="*"
SLEEP_SEC=2
INCLUDE_UNCLASSIFIED=false
ONLY_SAMPLES=""
EXPORT_NAME=""
EXTRA_ARGS=""
SUMMARY_FILE=""

ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-skip-bchg) SKIP_BCHG=false; shift ;;
    --only-needing) ONLY_NEED=true; shift ;;
    --pattern) PATTERN="${2:-*}"; shift 2 ;;
    --sleep) SLEEP_SEC="${2:-2}"; shift 2 ;;
    --include-unclassified) INCLUDE_UNCLASSIFIED=true; shift ;;
    --only-samples) ONLY_SAMPLES="${2:-}"; shift 2 ;;
    --export-name) EXPORT_NAME="${2:-}"; shift 2 ;;
    --extra) EXTRA_ARGS="${2:-}"; shift 2 ;;
    --summary) SUMMARY_FILE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '1,120p' "$0" | sed -n '1,80p'
      exit 0
      ;;
    *)
      if [[ -z "$ROOT" ]]; then ROOT="$1"; shift; else echo "[ERROR] Unexpected argument: $1" >&2; exit 1; fi ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  echo "[ERROR] Specify the runs root." >&2
  echo "Ex: tools/rerun_all_workflows.sh /workbench/runs --dry-run --only-needing" >&2
  exit 1
fi

if [[ ! -d "$ROOT" ]]; then
  echo "[ERROR] Directory not found: $ROOT" >&2
  exit 1
fi

needs_rerun() {
  # $1 = run_dir
  local run_dir="$1"
  # Locate a Nanopore-annotated VCF for inspection
  local vcf
  vcf=$(find "$run_dir" -maxdepth 3 -type f \( -name "*.ann.vcf" -o -name "*.ann.vcf.gz" \) -print -quit 2>/dev/null || true)
  if [[ -z "$vcf" ]]; then
    # No VCF found → rerun is useful
    return 0
  fi
  # Read first 200 lines (header + start) depending on compression
  local head_content=""
  if [[ "$vcf" == *.gz ]]; then
    head_content=$(zcat "$vcf" 2>/dev/null | head -n 200 2>/dev/null || true)
  else
    head_content=$(head -n 200 "$vcf" 2>/dev/null || true)
  fi
  if [[ -z "$head_content" ]]; then
    # Could not read the VCF → rerun to be safe
    return 0
  fi
  # Check INFO/AF header (new field)
  if ! echo "$head_content" | grep -qE '^##INFO=<ID=AF,.*Description="Allele Frequency from sample for haplocheck"'; then
    return 0
  fi
  # Check annotation prefixes
  if ! echo "$head_content" | grep -q 'MitoMap_'; then
    return 0
  fi
  if ! echo "$head_content" | grep -q 'gnomAD_'; then
    return 0
  fi
  # Looks up-to-date → no rerun needed
  return 1
}

if [[ -n "$SUMMARY_FILE" ]]; then
  # Initialize summary file with TSV header
  {
    echo -e "timestamp\trun_dir\tstatus\targs"
  } > "$SUMMARY_FILE"
fi

append_summary() {
  # $1=status, $2=run_dir, $3=args_str
  [[ -z "$SUMMARY_FILE" ]] && return 0
  local ts
  ts=$(date '+%F %T')
  printf '%s\t%s\t%s\t%s\n' "$ts" "$2" "$1" "$3" >> "$SUMMARY_FILE"
}

submit_one() {
  local run_dir="$1"
  local args=()
  $SKIP_BCHG && args+=("--skip-bchg")
  $INCLUDE_UNCLASSIFIED && args+=("--include-unclassified")
  [[ -n "$ONLY_SAMPLES" ]] && args+=("--only-samples" "$ONLY_SAMPLES")
  [[ -n "$EXPORT_NAME" ]] && args+=("--export-name" "$EXPORT_NAME")
  if [[ -n "$EXTRA_ARGS" ]]; then
    # shellcheck disable=SC2206
    extra_arr=( $EXTRA_ARGS )
    args+=("${extra_arr[@]}")
  fi
  local args_str
  args_str="${args[*]}"
  echo "[CMD] $SUBMIT_SCRIPT ${args_str} \"$run_dir\""
  if ! $DRY_RUN; then
    "$SUBMIT_SCRIPT" "${args[@]}" "$run_dir"
    append_summary "SUBMITTED" "$run_dir" "$args_str"
  else
    append_summary "DRY_RUN" "$run_dir" "$args_str"
  fi
  return 0
}

count_total=0
count_submitted=0
count_skipped=0

# Run discovery
shopt -s nullglob
for run_dir in "$ROOT"/$PATTERN/; do
  [[ -d "$run_dir" ]] || continue
  ((count_total++)) || true
  if $ONLY_NEED; then
    if needs_rerun "$run_dir"; then
      submit_one "$run_dir"
      ((count_submitted++)) || true
    else
      echo "[SKIP] $run_dir (already up to date)"
      ((count_skipped++)) || true
      append_summary "SKIPPED_UP_TO_DATE" "$run_dir" "--only-needing ${PATTERN:+--pattern $PATTERN}"
    fi
  else
    submit_one "$run_dir"
    ((count_submitted++)) || true
  fi
  sleep "$SLEEP_SEC"
done
shopt -u nullglob

echo "[SUMMARY] Total: $count_total | Submitted: $count_submitted | Skipped: $count_skipped"
