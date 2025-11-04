#!/bin/bash
# wf-finalize.sh - Send a single email when all Nanomito jobs are completed
#
# This script is intended to be submitted by wf-subwf.sh as a final step,
# with a dependency on all jobs launched for the run. It compiles a concise
# summary and the tail of relevant logs into the email body.
#
# Usage (submitted by wf-subwf.sh):
#   sbatch --dependency=afterok:<jobids...> \
#          --export=ALL,NANOMITO_DIR="$SCRIPT_DIR" \
#          --chdir="$RUN_DIR" \
#          --job-name="f${RUN_ID: -7}" \
#          --output="$PROCESS_DIR/slurm-$RUN_ID.final.out" \
#          $SCRIPT_DIR/wf-finalize.sh
#
set -euo pipefail

# --- Helpers ---------------------------------------------------------------
log_info() { echo "[INFO] $(date '+%H:%M:%S') - $1"; }
log_ok()   { echo "[OK]   $(date '+%H:%M:%S') - $1"; }
log_err()  { echo "[ERROR] $(date '+%H:%M:%S') - $1" >&2; }

cleanup() {
  local ec=$?
  if [ $ec -ne 0 ]; then
    log_err "Finalize failed with exit code $ec"
  fi
}
trap cleanup EXIT

# --- Locate repo dir and config ------------------------------------------
# Prefer NANOMITO_DIR when provided by parent
if [ -n "${NANOMITO_DIR:-}" ]; then
  SCRIPT_DIR="$NANOMITO_DIR"
else
  # Fallback autodetection
  SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
  if [ -L "$SCRIPT_PATH" ]; then
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  fi
  case "$SCRIPT_PATH" in
    /*) SCRIPT_DIR="$(dirname "$SCRIPT_PATH")" ;;
    *)  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)" ;;
  esac
fi

CONFIG_FILE="$SCRIPT_DIR/nanomito.config"
if [ ! -f "$CONFIG_FILE" ]; then
  log_err "Configuration file not found: $CONFIG_FILE"
  exit 1
fi
# shellcheck source=nanomito.config
source "$CONFIG_FILE"

# --- Context --------------------------------------------------------------
RUN_DIR=$(pwd)
RUN_ID=$(basename "$RUN_DIR")
PROCESS_DIR="$RUN_DIR/processing"

MAIL_TO="$MAIL_USER"
EMAIL_SUBJECT="[Nanomito] Fin du run $RUN_ID"
EMAIL_BODY_FILE="$PROCESS_DIR/email-$RUN_ID.txt"

mkdir -p "$PROCESS_DIR"
: > "$EMAIL_BODY_FILE"

append_section() {
  local title="$1"
  {
    echo ""
    echo "==================== $title ===================="
  } >> "$EMAIL_BODY_FILE"
}

append_file_tail() {
  local label="$1"
  local file="$2"
  local lines="${3:-60}"
  if [ -f "$file" ]; then
    {
      echo ""
      echo "----- $label (tail -n $lines) -----"
      tail -n "$lines" "$file" || true
    } >> "$EMAIL_BODY_FILE"
  fi
}

log_info "Preparing summary email body: $EMAIL_BODY_FILE"

{
  echo "Nanomito - Exécution terminée"
  echo "Run ID     : $RUN_ID"
  echo "Répertoire : $RUN_DIR"
  echo "Date       : $(date '+%Y-%m-%d %H:%M:%S')"
} >> "$EMAIL_BODY_FILE"

# Workflows summary TSV
SUMMARY_TSV="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"
if [ -f "$SUMMARY_TSV" ]; then
  append_section "Workflows summary"
  # Show as plain columns (replace tabs)
  sed 's/\t/    /g' "$SUMMARY_TSV" >> "$EMAIL_BODY_FILE"
fi

# Main logs (basecalling + subwf)
append_section "Journaux principaux"
append_file_tail "Basecalling (bchg)" "$PROCESS_DIR/slurm-$RUN_ID.bchg.out" 80
append_file_tail "Soumissions (subwf)" "$PROCESS_DIR/slurm-$RUN_ID.subwf.out" 80

# Per-sample logs (limit for email length)
MAX_SAMPLES=30
count=0
for d in "$PROCESS_DIR"/*/ ; do
  [ -d "$d" ] || continue
  sample=$(basename "$d")
  count=$((count+1))
  if [ $count -le $MAX_SAMPLES ]; then
  append_section "Échantillon: $sample"
  append_file_tail "demultmt (.out)" "$d/slurm-$sample.demultmt.out" 60
  append_file_tail "demultmt (.err)" "$d/slurm-$sample.demultmt.err" 40
  append_file_tail "modmito (.out)" "$d/slurm-$sample.modmito.out" 60
  append_file_tail "modmito (.err)" "$d/slurm-$sample.modmito.err" 40
  else
    REMAINING=$(( $(find "$PROCESS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l) - MAX_SAMPLES ))
    {
      echo ""
      echo "... $REMAINING échantillon(s) supplémentaire(s) — journaux omis pour l'email"
    } >> "$EMAIL_BODY_FILE"
    break
  fi
done

# --- Send email -----------------------------------------------------------
send_email() {
  local subject="$1"; shift
  local file="$1"; shift
  if command -v mail >/dev/null 2>&1; then
    mail -s "$subject" "$MAIL_TO" < "$file" || return 1
    return 0
  elif command -v mailx >/dev/null 2>&1; then
    mailx -s "$subject" "$MAIL_TO" < "$file" || return 1
    return 0
  elif command -v sendmail >/dev/null 2>&1; then
    {
      echo "To: $MAIL_TO"
      echo "Subject: $subject"
      echo "Content-Type: text/plain; charset=UTF-8"
      echo
      cat "$file"
    } | sendmail -t || return 1
    return 0
  else
    return 2
  fi
}

log_info "Sending email to $MAIL_TO"
if send_email "$EMAIL_SUBJECT" "$EMAIL_BODY_FILE"; then
  log_ok "Notification email sent"
else
  rc=$?
  if [ $rc -eq 2 ]; then
    log_err "No mailer found on system (mail/mailx/sendmail)."
  else
    log_err "Failed to send email with mailer (exit $rc)."
  fi
  log_info "Email body saved to: $EMAIL_BODY_FILE"
fi

log_ok "Finalize completed"
