#!/bin/bash
# wf-finalize.sh - Send a comprehensive email summary when all Nanomito jobs are completed
#
# This script is intended to be submitted by wf-subwf.sh as a final step,
# with a dependency on all jobs launched for the run. It compiles metrics,
# results, and key information into a structured email report.
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
EMAIL_SUBJECT="[Nanomito] Run $RUN_ID completed"
EMAIL_BODY_FILE="$PROCESS_DIR/email-$RUN_ID.txt"

mkdir -p "$PROCESS_DIR"
: > "$EMAIL_BODY_FILE"

# --- Helper functions -----------------------------------------------------
append_line() {
  echo "$1" >> "$EMAIL_BODY_FILE"
}

append_section() {
  local title="$1"
  {
    echo ""
    echo "==============================================================================="
    echo "  $title"
    echo "==============================================================================="
  } >> "$EMAIL_BODY_FILE"
}

count_vcf_variants() {
  local vcf_file="$1"
  if [ ! -f "$vcf_file" ]; then
    echo "N/A"
    return
  fi
  grep -v "^#" "$vcf_file" | wc -l | tr -d ' '
}

count_vcf_pass_variants() {
  local vcf_file="$1"
  if [ ! -f "$vcf_file" ]; then
    echo "N/A"
    return
  fi
  grep -v "^#" "$vcf_file" | awk '$7=="PASS"' | wc -l | tr -d ' '
}

extract_json_value() {
  local json_file="$1"
  local key_path="$2"
  if [ ! -f "$json_file" ]; then
    echo "N/A"
    return
  fi
  # Simple grep-based extraction (works for simple keys)
  grep -o "\"$key_path\"[[:space:]]*:[[:space:]]*[0-9.]*" "$json_file" 2>/dev/null | \
    grep -o '[0-9.]*$' || echo "N/A"
}

format_number() {
  local num="$1"
  if [[ "$num" =~ ^[0-9]+$ ]]; then
    printf "%'d" "$num" 2>/dev/null || echo "$num"
  else
    echo "$num"
  fi
}

log_info "Preparing comprehensive email summary: $EMAIL_BODY_FILE"

# --- Email Header ---------------------------------------------------------
{
  echo "==============================================================================="
  echo "                                                                               "
  echo "                    NANOMITO WORKFLOW COMPLETED                                "
  echo "                                                                               "
  echo "==============================================================================="
  echo ""
  echo "Run ID       : $RUN_ID"
  echo "Directory    : $RUN_DIR"
  echo "Completed at : $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
} >> "$EMAIL_BODY_FILE"

# --- 1. WORKFLOW EXECUTION SUMMARY ----------------------------------------
append_section "WORKFLOW EXECUTION SUMMARY"

SUMMARY_TSV="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"
if [ -f "$SUMMARY_TSV" ]; then
  # Calculate total runtime
  total_seconds=0
  while IFS=$'\t' read -r run_id sample_id workflow runtime; do
    if [ "$workflow" != "Workflow" ]; then
      # Convert hh:mm:ss to seconds
      IFS=: read -r hours minutes seconds <<< "$runtime"
      seconds_total=$((10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
      total_seconds=$((total_seconds + seconds_total))
    fi
  done < <(tail -n +2 "$SUMMARY_TSV")
  
  # Format total time
  total_hours=$((total_seconds / 3600))
  total_minutes=$(((total_seconds % 3600) / 60))
  total_secs=$((total_seconds % 60))
  
  append_line ""
  append_line "*** All jobs completed successfully! ***"
  append_line ""
  printf "%-40s : %02d:%02d:%02d\n" "Total workflow runtime" "$total_hours" "$total_minutes" "$total_secs" >> "$EMAIL_BODY_FILE"
  append_line ""
  append_line "Individual job runtimes:"
  append_line "+--------------------------------------+------------+--------------+"
  printf "| %-36s | %-10s | %-12s |\n" "Sample" "Workflow" "Runtime" >> "$EMAIL_BODY_FILE"
  append_line "+--------------------------------------+------------+--------------+"
  
  while IFS=$'\t' read -r run_id sample_id workflow runtime; do
    if [ "$workflow" != "Workflow" ]; then
      sample_display="${sample_id:-N/A}"
      if [ ${#sample_display} -gt 36 ]; then
        sample_display="${sample_display:0:33}..."
      fi
      printf "| %-36s | %-10s | %12s |\n" "$sample_display" "$workflow" "$runtime" >> "$EMAIL_BODY_FILE"
    fi
  done < <(tail -n +2 "$SUMMARY_TSV")
  
  append_line "+--------------------------------------+------------+--------------+"
else
  append_line ""
  append_line "WARNING: Workflow summary file not found"
fi

# --- 2. SEQUENCING RUN METRICS --------------------------------------------
append_section "SEQUENCING RUN METRICS"

# Try to find report file (JSON is easiest to parse, fallback to others)
REPORT_JSON=$(find "$RUN_DIR" -maxdepth 1 -name "report_*.json" | head -1)
REPORT_MD=$(find "$RUN_DIR" -maxdepth 1 -name "report_*.md" | head -1)

if [ -n "$REPORT_JSON" ] && [ -f "$REPORT_JSON" ]; then
  append_line ""
  # Extract key metrics from JSON
  reads_generated=$(grep -o '"reads_generated"[[:space:]]*:[[:space:]]*[0-9]*' "$REPORT_JSON" | grep -o '[0-9]*$' || echo "N/A")
  estimated_bases=$(grep -o '"estimated_bases"[[:space:]]*:[[:space:]]*[0-9]*' "$REPORT_JSON" | grep -o '[0-9]*$' || echo "N/A")
  
  if [ "$reads_generated" != "N/A" ]; then
    reads_formatted=$(format_number "$reads_generated")
    printf "  %-35s : %s\n" "Reads generated" "$reads_formatted" >> "$EMAIL_BODY_FILE"
  fi
  
  if [ "$estimated_bases" != "N/A" ]; then
    bases_formatted=$(format_number "$estimated_bases")
    # Convert to Gb
    if [[ "$estimated_bases" =~ ^[0-9]+$ ]]; then
      bases_gb=$(awk "BEGIN {printf \"%.2f\", $estimated_bases / 1000000000}")
      printf "  %-35s : %s (%.2f Gb)\n" "Estimated bases" "$bases_formatted" "$bases_gb" >> "$EMAIL_BODY_FILE"
    else
      printf "  %-35s : %s\n" "Estimated bases" "$bases_formatted" >> "$EMAIL_BODY_FILE"
    fi
  fi
  
elif [ -n "$REPORT_MD" ] && [ -f "$REPORT_MD" ]; then
  append_line ""
  append_line "Report found: $(basename "$REPORT_MD")"
  append_line "(Metrics extraction from Markdown not yet implemented)"
else
  append_line ""
  append_line "INFO: No report file found (report_*.json or report_*.md)"
fi

# --- 3. PER-SAMPLE RESULTS ------------------------------------------------
append_section "PER-SAMPLE RESULTS"

DEMULT_SUMMARY="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
HAPLOCHECK_SUMMARY="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"

if [ ! -f "$DEMULT_SUMMARY" ]; then
  append_line ""
  append_line "WARNING: Demultiplexing summary not found"
fi

if [ ! -f "$HAPLOCHECK_SUMMARY" ]; then
  append_line ""
  append_line "WARNING: Haplocheck summary not found"
fi

# Process each sample directory
sample_count=0
for sample_dir in "$PROCESS_DIR"/*/ ; do
  [ -d "$sample_dir" ] || continue
  
  sample=$(basename "$sample_dir")
  sample_count=$((sample_count + 1))
  
  append_line ""
  append_line "-------------------------------------------------------------------------------"
  printf "  Sample: %-66s\n" "$sample" >> "$EMAIL_BODY_FILE"
  append_line "-------------------------------------------------------------------------------"
  
  # Extract demultiplexing metrics
  if [ -f "$DEMULT_SUMMARY" ]; then
    chrM_reads=$(awk -v s="$sample" '$2==s {print $5}' "$DEMULT_SUMMARY")
    matching_both=$(awk -v s="$sample" '$2==s {print $6}' "$DEMULT_SUMMARY")
    
    if [ -n "$chrM_reads" ]; then
      append_line ""
      append_line "Alignment metrics:"
      printf "  %-40s : %15s\n" "Reads aligned to chrM" "$(format_number "$chrM_reads")" >> "$EMAIL_BODY_FILE"
      printf "  %-40s : %15s\n" "Reads matching both (ref + chrM)" "$(format_number "$matching_both")" >> "$EMAIL_BODY_FILE"
    fi
  fi
  
  # Extract haplogroup information
  if [ -f "$HAPLOCHECK_SUMMARY" ]; then
    # Parse TSV with quoted fields
    haplocheck_line=$(awk -v s="$sample" -F'\t' '$1 == "\"" s "\"" || $1 == s {print}' "$HAPLOCHECK_SUMMARY")
    
    if [ -n "$haplocheck_line" ]; then
      contamination_status=$(echo "$haplocheck_line" | awk -F'\t' '{print $2}' | tr -d '"')
      major_haplogroup=$(echo "$haplocheck_line" | awk -F'\t' '{print $10}' | tr -d '"')
      minor_haplogroup=$(echo "$haplocheck_line" | awk -F'\t' '{print $12}' | tr -d '"')
      
      append_line ""
      append_line "Haplogroup analysis:"
      printf "  %-40s : %15s\n" "Contamination Status" "$contamination_status" >> "$EMAIL_BODY_FILE"
      printf "  %-40s : %15s\n" "Major Haplogroup" "$major_haplogroup" >> "$EMAIL_BODY_FILE"
      
      if [ "$major_haplogroup" != "$minor_haplogroup" ] && [ -n "$minor_haplogroup" ]; then
        printf "  %-40s : %15s\n" "Minor Haplogroup" "$minor_haplogroup" >> "$EMAIL_BODY_FILE"
      fi
    fi
  fi
  
  # Count variants in VCF
  vcf_file="$sample_dir/${sample}.ann.vcf"
  if [ -f "$vcf_file" ]; then
    total_variants=$(count_vcf_variants "$vcf_file")
    pass_variants=$(count_vcf_pass_variants "$vcf_file")
    
    append_line ""
    append_line "Variant calling:"
    printf "  %-40s : %15s\n" "Total variants" "$total_variants" >> "$EMAIL_BODY_FILE"
    printf "  %-40s : %15s\n" "PASS variants" "$pass_variants" >> "$EMAIL_BODY_FILE"
  fi
  
  # Check for important output files
  append_line ""
  append_line "Key output files:"
  
  bam_file="${sample}.chrM.sup,5mC_5hmC,6mA.sorted.bam"
  ann_tsv="${sample}.ann.tsv"
  ann_vcf="${sample}.ann.vcf"
  
  if [ -f "$sample_dir/$bam_file" ]; then
    bam_size=$(du -h "$sample_dir/$bam_file" | cut -f1)
    printf "  [YES] %-40s (%s)\n" "Sorted BAM" "$bam_size" >> "$EMAIL_BODY_FILE"
  else
    printf "  [NO ] %-40s\n" "Sorted BAM - NOT FOUND" >> "$EMAIL_BODY_FILE"
  fi
  
  if [ -f "$sample_dir/$ann_vcf" ]; then
    printf "  [YES] %-40s\n" "Annotated VCF" >> "$EMAIL_BODY_FILE"
  else
    printf "  [NO ] %-40s\n" "Annotated VCF - NOT FOUND" >> "$EMAIL_BODY_FILE"
  fi
  
  if [ -f "$sample_dir/$ann_tsv" ]; then
    printf "  [YES] %-40s\n" "Annotated TSV" >> "$EMAIL_BODY_FILE"
  else
    printf "  [NO ] %-40s\n" "Annotated TSV - NOT FOUND" >> "$EMAIL_BODY_FILE"
  fi
  
  # Check for errors in logs
  demultmt_err="$sample_dir/slurm-${sample}.demultmt.err"
  modmito_err="$sample_dir/slurm-${sample}.modmito.err"
  
  error_count=0
  if [ -f "$demultmt_err" ]; then
    error_count=$((error_count + $(grep -ci "error\|failed\|exception" "$demultmt_err" 2>/dev/null || echo 0)))
  fi
  if [ -f "$modmito_err" ]; then
    error_count=$((error_count + $(grep -ci "error\|failed\|exception" "$modmito_err" 2>/dev/null || echo 0)))
  fi
  
  if [ $error_count -gt 0 ]; then
    append_line ""
    append_line "WARNING: $error_count potential error(s) found in logs"
    append_line "    Check: $demultmt_err"
    append_line "    Check: $modmito_err"
  fi
  
done

if [ $sample_count -eq 0 ]; then
  append_line ""
  append_line "WARNING: No sample directories found in processing/"
else
  append_line ""
  append_line "-------------------------------------------------------------------------------"
  append_line "Total samples processed: $sample_count"
fi

# --- 4. SUMMARY FILES LOCATION --------------------------------------------
append_section "SUMMARY FILES"

append_line ""
append_line "Main directory:"
append_line "  $RUN_DIR"
append_line ""
append_line "Processing directory:"
append_line "  $PROCESS_DIR"
append_line ""
append_line "Key summary files:"

if [ -f "$SUMMARY_TSV" ]; then
  append_line "  [YES] workflows_summary.$RUN_ID.tsv"
else
  append_line "  [NO ] workflows_summary.$RUN_ID.tsv (not found)"
fi

if [ -f "$DEMULT_SUMMARY" ]; then
  append_line "  [YES] demult_summary.$RUN_ID.tsv"
else
  append_line "  [NO ] demult_summary.$RUN_ID.tsv (not found)"
fi

if [ -f "$HAPLOCHECK_SUMMARY" ]; then
  append_line "  [YES] haplocheck_summary.$RUN_ID.tsv"
else
  append_line "  [NO ] haplocheck_summary.$RUN_ID.tsv (not found)"
fi

# --- 5. FOOTER ------------------------------------------------------------
{
  echo ""
  echo "==============================================================================="
  echo "  End of Nanomito Report"
  echo "  For detailed logs, check the processing/ directory"
  echo "==============================================================================="
} >> "$EMAIL_BODY_FILE"

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
