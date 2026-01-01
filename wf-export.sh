#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
#SBATCH --job-name=export
#SBATCH --time=00:30:00
#SBATCH --mail-type=FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_80
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

# wf-export.sh - SLURM wrapper to export Nanomito results
# Usage (sbatch): wf-export.sh <run_dir> [export_name]

set -euo pipefail

# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" describe --tags 2>/dev/null || echo 'unknown')"
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

log_info()   { echo "[INFO] $(date '+%H:%M:%S') - $1"; }
log_ok()     { echo "[OK]   $(date '+%H:%M:%S') - $1"; }
log_error()  { echo "[ERROR] $(date '+%H:%M:%S') - $1" >&2; }

if [ $# -lt 1 ]; then
  log_error "Missing argument: run directory"
  echo "Usage: wf-export.sh <run_dir> [export_name]" >&2
  exit 2
fi

RUN_DIR=$(cd "$1" && pwd)
RUN_NAME="${2:-}"  # optional export name override
RUN_ID=$(basename "$RUN_DIR")

# Use NANOMITO_DIR from SLURM export if available, otherwise resolve from script location
SCRIPT_DIR="${NANOMITO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
EXPORT_SCRIPT="$SCRIPT_DIR/tools/export_results.sh"

if [ ! -x "$EXPORT_SCRIPT" ]; then
  # export_results.sh is bash script; executability not mandatory but check exists
  if [ ! -f "$EXPORT_SCRIPT" ]; then
    log_error "export_results.sh not found at $EXPORT_SCRIPT"
    exit 1
  fi
fi

log_info "Workflow: wf-export v.$VERSION by $AUTHOR"
log_info "Run directory: $RUN_DIR"
if [ -n "$RUN_NAME" ]; then
  log_info "Export name override: $RUN_NAME"
fi

if bash "$EXPORT_SCRIPT" "$RUN_DIR" "$RUN_NAME"; then
  log_ok "Export completed for $RUN_ID"
else
  rc=$?
  log_error "Export failed for $RUN_ID (exit $rc)"
  exit $rc
fi
