#!/bin/bash
# shellcheck disable=SC2034
# SPDX-License-Identifier: CECILL-2.1
# wf-finalize.sh - Generate final email summary for completed Nanomito runs
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
#SBATCH --time=01:00:00
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
# Manual usage:
#   wf-finalize.sh [--reports-only] [/path/to/run/dir]
#
set -euo pipefail

# --- CLI Options ---------------------------------------------------------
REPORTS_ONLY=false
RUN_DIR_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reports-only)
      REPORTS_ONLY=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -z "$RUN_DIR_ARG" ]]; then
        RUN_DIR_ARG="$1"
        shift
      else
        echo "Too many arguments. Usage: wf-finalize.sh [--reports-only] [/path/to/run/dir]" >&2
        exit 1
      fi
      ;;
  esac
done

# --- Helpers ---------------------------------------------------------------
log_info() { echo "[INFO] $(date '+%H:%M:%S') - $1"; }
log_ok()   { echo "[OK]   $(date '+%H:%M:%S') - $1"; }
log_err()  { echo "[ERROR] $(date '+%H:%M:%S') - $1" >&2; }
log_warning() { echo "[WARN] $(date '+%H:%M:%S') - $1"; }

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
# shellcheck disable=SC1091
source "$CONFIG_FILE"

# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$SCRIPT_DIR" describe --tags 2>/dev/null || echo 'unknown')"

# --- Context --------------------------------------------------------------
# Use provided run directory argument or default to current directory
if [[ -n "$RUN_DIR_ARG" ]]; then
  RUN_DIR="$(cd "$RUN_DIR_ARG" && pwd)" || {
    log_err "Invalid run directory: $RUN_DIR_ARG"
    exit 1
  }
else
  RUN_DIR=$(pwd)
fi

RUN_ID=$(basename "$RUN_DIR")
PROCESS_DIR="$RUN_DIR/processing"

# Validate that processing directory exists or can be created
if [[ ! -d "$PROCESS_DIR" ]]; then
  log_info "Creating processing directory: $PROCESS_DIR"
  mkdir -p "$PROCESS_DIR" || {
    log_err "Failed to create processing directory: $PROCESS_DIR"
    exit 1
  }
fi

MAIL_TO="$MAIL_USER"
EMAIL_SUBJECT="[Nanomito] Run $RUN_ID completed"
EMAIL_BODY_FILE="$PROCESS_DIR/report-$RUN_ID.html"

mkdir -p "$PROCESS_DIR"
: > "$EMAIL_BODY_FILE"

# --- Helper functions (defined early for --reports-only mode) ------------
append_line() {
  echo "$1" >> "$EMAIL_BODY_FILE"
}

append_html() {
  echo "$1" >> "$EMAIL_BODY_FILE"
}

start_html() {
  cat >> "$EMAIL_BODY_FILE" << 'EOF'
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
    line-height: 1.6;
    color: #333;
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    background-color: #f5f5f5;
  }
  .container {
    background-color: white;
    border-radius: 8px;
    padding: 20px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
  .header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 30px 20px;
    border-radius: 8px;
    text-align: center;
    margin: -20px -20px 20px -20px;
  }
  .header h1 {
    margin: 0;
    font-size: 24px;
    font-weight: 600;
  }
  .header .subtitle {
    margin-top: 10px;
    opacity: 0.9;
    font-size: 14px;
  }
  .section {
    margin: 25px 0;
    padding: 15px;
    background-color: #f8f9fa;
    border-left: 4px solid #667eea;
    border-radius: 4px;
  }
  .section-title {
    font-size: 18px;
    font-weight: 600;
    color: #667eea;
    margin: 0 0 15px 0;
  }
  .metric-row {
    display: flex;
    justify-content: space-between;
    padding: 8px 0;
    border-bottom: 1px solid #e9ecef;
  }
  .metric-row:last-child {
    border-bottom: none;
  }
  .metric-label {
    color: #6c757d;
    font-weight: 500;
  }
  .metric-value {
    font-family: 'Courier New', Consolas, monospace;
    font-weight: 600;
    color: #495057;
  }
  .success {
    color: #28a745;
  }
  .warning {
    color: #ffc107;
  }
  .error {
    color: #dc3545;
  }
  .info {
    color: #17a2b8;
  }
  .badge {
    display: inline-block;
    padding: 4px 8px;
    border-radius: 12px;
    font-size: 12px;
    font-weight: 600;
    margin-left: 8px;
  }
  .badge-ok {
    background-color: #d4edda;
    color: #155724;
  }
  .badge-error {
    background-color: #f8d7da;
    color: #721c24;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 10px 0;
    font-family: 'Courier New', Consolas, monospace;
    font-size: 13px;
  }
  th {
    background-color: #667eea;
    color: white;
    padding: 10px;
    text-align: left;
    font-weight: 600;
  }
  td {
    padding: 8px 10px;
    border-bottom: 1px solid #dee2e6;
  }
  tr:nth-child(even) {
    background-color: #f8f9fa;
  }
  .sample-card {
    background-color: white;
    border: 1px solid #dee2e6;
    border-radius: 6px;
    padding: 15px;
    margin: 15px 0;
  }
  .sample-header {
    font-size: 16px;
    font-weight: 600;
    color: #495057;
    margin-bottom: 10px;
    padding-bottom: 10px;
    border-bottom: 2px solid #667eea;
  }
  .file-list {
    margin: 10px 0;
  }
  .file-item {
    padding: 5px 0;
    font-family: 'Courier New', Consolas, monospace;
    font-size: 13px;
  }
  .footer {
    margin-top: 30px;
    padding-top: 20px;
    border-top: 2px solid #dee2e6;
    text-align: center;
    color: #6c757d;
    font-size: 14px;
  }
  @media (max-width: 600px) {
    body {
      padding: 10px;
    }
    .container {
      padding: 15px;
    }
    .header {
      padding: 20px 15px;
      margin: -15px -15px 15px -15px;
    }
    .header h1 {
      font-size: 20px;
    }
    .metric-row {
      flex-direction: column;
      gap: 4px;
    }
    table {
      font-size: 11px;
    }
    th, td {
      padding: 6px 8px;
    }
  }
</style>
</head>
<body>
<div class="container">
EOF
}

end_html() {
  cat >> "$EMAIL_BODY_FILE" << 'EOF'
</div>
<script>
  // Update filter label text when checkbox state changes
  const filterCheckbox = document.getElementById('passOnly');
  const filterLabel = document.getElementById('filterLabel');
  
  if (filterCheckbox && filterLabel) {
    // Initialize label based on current checkbox state
    function updateLabel() {
      filterLabel.textContent = filterCheckbox.checked ? 'Show all variants' : 'Show PASS only';
    }
    
    // Update on change event (works well on iOS)
    filterCheckbox.addEventListener('change', updateLabel);
    
    // Initialize on page load
    updateLabel();
  }
</script>
</body>
</html>
EOF
}

# --- HTML helpers for per-sample reports --------------------------------
sanitize_html() {
  local s=${1:-}
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  echo "$s"
}

tsv_to_html_table() {
  local tsv_file="$1"
  local coloring="$2" # "disease" | "none"
  local table_id="${3:-}" # optional table id
  local vcf_file="${4:-}" # optional VCF file for tooltips
  
  if [ ! -f "$tsv_file" ]; then
    echo "<p>File not found: $(basename "$tsv_file")</p>"
    return 0
  fi
  
  # Enrich TSV: add END;SVLEN to <DEL> in ALT column from VCF
  local enriched_tsv
  enriched_tsv=$(mktemp)
  if [ -n "$vcf_file" ] && [ -f "$vcf_file" ]; then
    python3 - "$tsv_file" "$vcf_file" "$enriched_tsv" << 'PYEND'
import sys, re
tsv_path, vcf_path, out_path = sys.argv[1:4]

# Load VCF variants into a dict {(CHROM, POS): (END, SVLEN)}
vcf_dels = {}
try:
    with open(vcf_path) as f:
        for line in f:
            if line.startswith('#'):
                continue
            fields = line.rstrip('\n').split('\t')
            if len(fields) < 8:
                continue
            chrom, pos, _, ref, alt, _, _, info = fields[0:8]
            if '<DEL>' in alt or alt.startswith('<DEL'):
                # Extract END and SVLEN from INFO
                end = svlen = None
                for kv in info.split(';'):
                    if kv.startswith('END='):
                        end = kv.split('=')[1]
                    elif kv.startswith('SVLEN='):
                        svlen = kv.split('=')[1]
                if end and svlen:
                    vcf_dels[(chrom, pos)] = (end, svlen)
except:
    pass

# Process TSV, enriching ALT column
with open(tsv_path) as fin, open(out_path, 'w') as fout:
    for line_num, line in enumerate(fin, 1):
        row = line.rstrip('\n').split('\t')
        
        if line_num == 1:  # Header
            fout.write(line)
        else:
            # ALT is typically column 5 (index 4), but find it
            if len(row) > 4:
                alt_col = 4  # Default to column 5
                if '<DEL>' in row[alt_col] or row[alt_col].startswith('<DEL'):
                    if len(row) > 1:
                        chrom = 'chrM'
                        pos = row[1] if len(row) > 1 else None
                        if pos and (chrom, pos) in vcf_dels:
                            end, svlen = vcf_dels[(chrom, pos)]
                            row[alt_col] = f'<DEL;END={end};SVLEN={svlen}>'
            fout.write('\t'.join(row) + '\n')
PYEND
  else
    cp "$tsv_file" "$enriched_tsv"
  fi
  
  tsv_file="$enriched_tsv"
  
  # Extract VCF header descriptions if VCF provided
  local tooltips_file=""
  if [ -n "$vcf_file" ] && [ -f "$vcf_file" ]; then
    tooltips_file=$(mktemp)
    
    # Extract FORMAT and INFO descriptions (no conda needed, just grep/sed)
    grep '^##FORMAT=<ID=' "$vcf_file" 2>/dev/null | while IFS= read -r line; do
      id=$(echo "$line" | sed -n 's/.*ID=\([^,]*\).*/\1/p')
      desc=$(echo "$line" | sed -n 's/.*Description="\([^"]*\)".*/\1/p')
      echo -e "$id\t$desc"
    done > "$tooltips_file"
    
    grep '^##INFO=<ID=' "$vcf_file" 2>/dev/null | while IFS= read -r line; do
      id=$(echo "$line" | sed -n 's/.*ID=\([^,]*\).*/\1/p')
      desc=$(echo "$line" | sed -n 's/.*Description="\([^"]*\)".*/\1/p')
      # Prefix INFO fields that don't already have a prefix
      if [[ ! "$id" =~ ^(MitoMap_|gnomAD_) ]]; then
        id="INFO_$id"
      fi
      echo -e "$id\t$desc"
    done >> "$tooltips_file"
    
    # Add basic VCF field descriptions
    cat >> "$tooltips_file" << 'EOVCF'
CHROM	Chromosome name
POS	Position (1-based)
ID	Variant identifier
REF	Reference allele
ALT	Alternate allele(s)
QUAL	Phred-scaled quality score
FILTER	Filter status
EOVCF
  fi
  
  awk -v FS=$'\t' -v coloring="${coloring}" -v table_id="${table_id}" -v tooltips_file="${tooltips_file}" '
    function esc(x) { 
      gsub(/&/, "AMPERSAND_PLACEHOLDER", x)
      gsub(/</, "LESSTHAN_PLACEHOLDER", x)
      gsub(/>/, "GREATERTHAN_PLACEHOLDER", x)
      gsub(/AMPERSAND_PLACEHOLDER/, "\\&amp;", x)
      gsub(/LESSTHAN_PLACEHOLDER/, "\\&lt;", x)
      gsub(/GREATERTHAN_PLACEHOLDER/, "\\&gt;", x)
      return x 
    }
    function toup(x,  i,c,r){ r=""; for(i=1;i<=length(x);i++){c=substr(x,i,1); r=r ((c>="a" && c<="z")? sprintf("%c", ord(c)-32): c)}; return r }
    function ord(c){ return index("\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", c)-1 }
    BEGIN {
      # Force tab as field separator robustly (ASCII 9), regardless of shell quoting
      FS = sprintf("%c", 9)
      filter_idx=0; alt_idx=0; end_idx=0; svlen_idx=0;
      
      # Load tooltips from file if provided
      if (tooltips_file != "") {
        while ((getline line < tooltips_file) > 0) {
          split(line, parts, "\t")
          if (length(parts) >= 2) {
            tooltips[parts[1]] = parts[2]
          }
        }
        close(tooltips_file)
      }
      
      if (table_id) {
        # Add both id and class so CSS toggles can target the table
        print "<table id=\"" table_id "\" class=\"" table_id "\">"
      } else {
        print "<table>"
      }
    }
    NR==1 {
      filter_idx=0;
      print "<thead><tr>";
      for (i=1; i<=NF; i++) {
        hdr=$i; uhdr=toupper(hdr);
        if (uhdr=="FILTER" || uhdr=="FILTERS" || index(uhdr,"FILTER")>0) { filter_idx=i }
        if (uhdr=="ALT") alt_idx=i;
        if (uhdr=="END") end_idx=i;
        if (uhdr=="SVLEN") svlen_idx=i;
        
        # Add tooltip if available
        tooltip = ""
        if (hdr in tooltips) {
          tooltip = " title=\"" esc(tooltips[hdr]) "\""
        }
        
        printf "<th%s>%s</th>", tooltip, esc($i)
      }
      print "</tr></thead><tbody>";
      next
    }
    NR>1 {
      rowclass="";
      if (coloring=="disease") {
        line=$0
        if (line ~ /Cfrm-\[P\]/) rowclass="pathogenic";
        else if (line ~ /Cfrm-\[LP\]/) rowclass="likely-pathogenic";
        else if (line ~ /Cfrm-\[B\]/) rowclass="benign";
        for (i=1;i<=NF;i++) { if ($i=="<DEL>" || $i ~ /^<DEL/) { rowclass="deletion" } }
      }
      passclass="";
      if (filter_idx>0) {
        fv=$filter_idx; gsub(/^\s+|\s+$/, "", fv); u=toupper(fv);
        if (u=="PASS" || u=="." || u=="") passclass=" is-pass";
      }
      printf "<tr class=\"%s%s\">", (rowclass!=""?rowclass:""), passclass;
      for (i=1; i<=NF; i++) {
        val=$i
        printf "<td>%s</td>", esc(val)
      }
      print "</tr>"
    }
    END { print "</tbody></table>" }
  ' "${tsv_file}"
  
  # Clean up enriched TSV temp file
  [ "$tsv_file" != "$1" ] && rm -f "$tsv_file"
  
  # Clean up tooltips temp file
  [ -n "$tooltips_file" ] && rm -f "$tooltips_file"
}

generate_sample_html_report() {
  local sample_dir="$1"
  local sample="$2"
  local demult_summary="$3"
  local haplo_summary="$4"

  local report_file="$sample_dir/report-$sample.html"
  local ann_vcf="$sample_dir/${sample}.ann.vcf"
  local ann_tsv="$sample_dir/${sample}.ann.tsv"
  local demultmt_err="$sample_dir/slurm-${sample}.demultmt.err"
  local modmito_err="$sample_dir/slurm-${sample}.modmito.err"

  # Metrics
  local chrM_reads="" matching_both=""
  if [ -f "$demult_summary" ]; then
    # Use last matching line to get most recent values (avoid duplicates)
    chrM_reads=$(awk -v s="$sample" -F'\t' '$2==s {val=$5} END {print val}' "$demult_summary")
    matching_both=$(awk -v s="$sample" -F'\t' '$2==s {val=$6} END {print val}' "$demult_summary")
  fi
  local total_variants pass_variants
  total_variants=$(count_vcf_variants "$ann_vcf")
  pass_variants=$(count_vcf_pass_variants "$ann_vcf")

  # Run metrics from report JSON
  local read_count="N/A" basecalled_pass_read_count="N/A" basecalled_pass_bases="N/A"
  REPORT_JSON=$(find "$RUN_DIR" -type f -name "report_*.json" 2>/dev/null | sort -r | head -1)
  if [ -n "$REPORT_JSON" ] && [ -f "$REPORT_JSON" ]; then
    local metrics_output
    metrics_output=$(python3 << PYEOF
import json
try:
    with open("$REPORT_JSON") as f:
        data = json.load(f)
    acq = data.get("acquisitions", [])
    if acq:
        ys = acq[-1].get("acquisition_run_info", {}).get("yield_summary", {})
        rc = str(ys.get("read_count", "N/A"))
        pb = str(ys.get("basecalled_pass_bases", "N/A"))
        pr = str(ys.get("basecalled_pass_read_count", "N/A"))
        print(f"{rc}|{pb}|{pr}")
    else:
        print("N/A|N/A|N/A")
except Exception as e:
    print("N/A|N/A|N/A")
PYEOF
)
    read_count=$(echo "$metrics_output" | cut -d'|' -f1)
    basecalled_pass_bases=$(echo "$metrics_output" | cut -d'|' -f2)
    basecalled_pass_read_count=$(echo "$metrics_output" | cut -d'|' -f3)
  fi

  # Haplogroup status/major/minor from individual haplocheck file
  local contamination_status="N/A" major_haplogroup="N/A" minor_haplogroup=""
  local haplo_raw="$sample_dir/haplo/${sample}-haplocheck.raw.txt"
  if [ -f "$haplo_raw" ]; then
    # Read the data line (skip header)
    haplocheck_line=$(tail -n1 "$haplo_raw")
    if [ -n "$haplocheck_line" ]; then
      contamination_status=$(echo "$haplocheck_line" | awk -F'\t' '{print $2}' | tr -d '"')
      major_haplogroup=$(echo "$haplocheck_line" | awk -F'\t' '{print $10}' | tr -d '"')
      minor_haplogroup=$(echo "$haplocheck_line" | awk -F'\t' '{print $12}' | tr -d '"')
    fi
  fi
  # Combine major/minor haplogroup for display
  local display_haplogroup="$major_haplogroup"
  if [ -n "$minor_haplogroup" ] && [ "$minor_haplogroup" != "" ] && [ "$minor_haplogroup" != "$major_haplogroup" ]; then
    display_haplogroup="$major_haplogroup / $minor_haplogroup"
  fi

  # Count highlighted variants (pathogenic, likely-pathogenic, benign, deletion)
  local highlighted_count=0
  if [ -f "$ann_tsv" ]; then
    highlighted_count=$(awk -F'\t' 'NR>1 && ($10 ~ /Cfrm-\[P\]/ || $10 ~ /Cfrm-\[LP\]/ || $10 ~ /Cfrm-\[B\]/ || $5 ~ /^<DEL/) {count++} END {print count+0}' "$ann_tsv")
  fi

  # Count deletions (with deduplication like in the table display)
  local deletions_total=0
  local del_file="$sample_dir/varcall/${sample}.baldur_del.txt"
  if [ -f "$del_file" ]; then
    # Apply same deduplication logic as in the table: count unique start-stop pairs
    deletions_total=$(awk 'BEGIN{FS="\t"} \
         !/^#/ && NF>=3 { \
           a=$1+0; b=$2+0; \
           if (a==0 && b==0) next; \
           start=(a<b?a:b); stop=(a<b?b:a); \
           key=start "\t" stop; \
           if (!(key in seen)) { seen[key]=1; count++ } \
         } \
         END {print count+0}' "$del_file")
  fi

  # Count deletions in variants (highlighted deletions with <DEL>)
  local deletions_highlighted=0
  if [ -f "$ann_tsv" ]; then
    deletions_highlighted=$(awk -F'\t' 'NR>1 && $5 ~ /^<DEL/ {count++} END {print count+0}' "$ann_tsv")
  fi

  # Logs: errors and warnings
  local err_count=0 warn_count=0
  if [ -f "$demultmt_err" ]; then
    c=$(grep -ci "error\|failed\|exception" "$demultmt_err" 2>/dev/null || echo 0); [[ "$c" =~ ^[0-9]+$ ]] || c=0; err_count=$((err_count + c))
    w=$(grep -ci "warn" "$demultmt_err" 2>/dev/null || echo 0); [[ "$w" =~ ^[0-9]+$ ]] || w=0; warn_count=$((warn_count + w))
  fi
  if [ -f "$modmito_err" ]; then
    c=$(grep -ci "error\|failed\|exception" "$modmito_err" 2>/dev/null || echo 0); [[ "$c" =~ ^[0-9]+$ ]] || c=0; err_count=$((err_count + c))
    w=$(grep -ci "warn" "$modmito_err" 2>/dev/null || echo 0); [[ "$w" =~ ^[0-9]+$ ]] || w=0; warn_count=$((warn_count + w))
  fi

  # Build HTML
  cat > "$report_file" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Nanomito Sample Report - $sample</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif; background:#f5f5f5; color:#333; padding:20px; }
    .container { max-width: 1100px; margin:0 auto; background:white; padding:24px; border-radius:8px; box-shadow:0 2px 4px rgba(0,0,0,0.1); }
    header { border-bottom:3px solid #2c3e50; padding-bottom:12px; margin-bottom:20px; }
    h1 { margin:0; font-size:22px; color:#2c3e50; }
    .meta { color:#7f8c8d; font-size:11px; line-height:1.5; }
    .meta .run-metrics { margin-top:6px; color:#555; font-size:10px; }
    .summary { background:#ecf0f1; padding:16px; border-radius:6px; margin-bottom:24px; }
    .stats-grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(180px,1fr)); gap:12px; }
    .stat-card { background:white; padding:12px; border-radius:6px; border-left:4px solid #3498db; }
    .stat-card.align { border-left-color:#3498db; }
    .stat-card.haplo { border-left-color:#9b59b6; }
    .stat-card.variants { border-left-color:#2ecc71; }
    .stat-card.highlighted { border-left-color:#e74c3c; }
    .stat-card.deletions { border-left-color:#27ae60; }
    .stat-label { font-size:11px; color:#7f8c8d; text-transform:uppercase; }
    .stat-value { font-size:18px; font-weight:600; color:#2c3e50; }
    .stat-value.highlight-red { color:#e74c3c; }
    .log-status { margin-top:10px; padding:10px; border-radius:5px; font-weight:600; }
    .log-status.success { background:#d4edda; color:#155724; }
    .log-status.warning { background:#fff3cd; color:#856404; }
    .log-status.error { background:#f8d7da; color:#721c24; }
    .section { margin-bottom:26px; }
    .section h2 { color:#2c3e50; font-size:18px; border-bottom:2px solid #ecf0f1; padding-bottom:6px; }
    .dorado-params { background:#f8f9fa; padding:10px; border-radius:5px; margin:10px 0; font-size:11px; border-left:3px solid #3498db; }
    .dorado-params code { background:#e9ecef; padding:2px 5px; border-radius:3px; font-family:'Courier New',Consolas,monospace; font-size:10px; }
    .baldur-params { background:#f8f9fa; padding:10px; border-radius:5px; margin:10px 0; font-size:11px; border-left:3px solid #27ae60; }
    .baldur-params code { background:#e9ecef; padding:2px 5px; border-radius:3px; font-family:'Courier New',Consolas,monospace; font-size:10px; }
    .haplocheck-params { background:#f8f9fa; padding:10px; border-radius:5px; margin:10px 0; font-size:11px; border-left:3px solid #9b59b6; }
    .haplocheck-params code { background:#e9ecef; padding:2px 5px; border-radius:3px; font-family:'Courier New',Consolas,monospace; font-size:10px; }
    table { width:100%; border-collapse:collapse; font-size:12px; background:white; overflow-x:auto; display:block; }
    table.haplogroup-table th { width:40%; }
    table.haplogroup-table td { width:60%; }
    table.deletions-table { margin-top:5px; font-size:11px; }
    .file-list { margin:10px 0; }
    .file-item { padding:5px 0; font-family:'Courier New',Consolas,monospace; font-size:13px; word-break:break-all; }
    .badge { display:inline-block; padding:2px 6px; border-radius:3px; font-size:11px; font-weight:600; margin-right:6px; }
    .badge-ok { background:#d4edda; color:#155724; }
    .badge-error { background:#f8d7da; color:#721c24; }
    thead { background:#34495e; color:white; position:sticky; top:0; }
    th { padding:8px; text-align:left; border:1px solid #2c3e50; white-space:nowrap; }
    td { padding:6px; border:1px solid #ddd; max-width:200px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    td:hover { white-space:normal; word-wrap:break-word; }
    tbody tr:nth-child(even) { background:#f8f9fa; }
    tbody tr:hover { background:#e8f4f8; }
    tr.pathogenic { background:#ffebee !important; }
    tr.likely-pathogenic { background:#fff3e0 !important; }
    tr.benign { background:#fffde7 !important; }
    tr.deletion { background:#e6e6fa !important; }
    tr.hidden { display:none; }
    /* PASS-only toggle without JS: hide non-PASS rows when checkbox is checked */
    .pass-toggle { position:absolute; left:-9999px; }
    .pass-toggle:checked ~ table.variants-table tbody tr:not(.is-pass) { display:none; }
    .filter-toggle { display:inline-block; margin:10px 0; padding:8px 12px; background:#667eea; color:white; border:none; border-radius:4px; cursor:pointer; font-size:13px; }
    .filter-toggle:hover { background:#5568d3; }
    
    /* Mobile responsive */
    @media (max-width: 768px) {
      body { padding:10px; }
      .container { padding:12px; }
      h1 { font-size:18px; }
      .meta { font-size:10px; }
      .stats-grid { grid-template-columns: repeat(auto-fit, minmax(140px,1fr)); gap:8px; }
      .stat-card { padding:8px; }
      .stat-label { font-size:10px; }
      .stat-value { font-size:16px; }
      .section h2 { font-size:16px; }
      table { font-size:10px; }
      th, td { padding:4px; font-size:10px; }
      td { max-width:120px; }
      .filter-toggle { font-size:12px; padding:6px 10px; }
      .file-item { font-size:11px; }
    }
    
    @media (max-width: 480px) {
      .stats-grid { grid-template-columns: 1fr; }
      table { font-size:9px; }
      th, td { padding:3px; font-size:9px; }
      td { max-width:80px; }
    }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Nanomito Sample Report — $sample</h1>
      <div class="meta">
        Generated: $(date '+%Y-%m-%d %H:%M:%S')<br>
        Run: $RUN_ID • Total reads: $(format_number "$read_count") • Passed reads: $(format_number "$basecalled_pass_read_count") • Passed bases: $(format_number "$basecalled_pass_bases")
      </div>
    </header>
    <div class="summary">
      <div class="stats-grid">
        <div class="stat-card align"><div class="stat-label">Alignment / chrM reads</div><div class="stat-value">$(format_number "${chrM_reads:-N/A}")</div></div>
        <div class="stat-card align"><div class="stat-label">Alignment / Matching both</div><div class="stat-value">$(format_number "${matching_both:-N/A}")</div></div>
        <div class="stat-card haplo"><div class="stat-label">CONTAMINATION</div><div class="stat-value">$(sanitize_html "$contamination_status")</div></div>
        <div class="stat-card haplo"><div class="stat-label">HAPLOGROUP</div><div class="stat-value">$(sanitize_html "$display_haplogroup")</div></div>
        <div class="stat-card variants"><div class="stat-label">Variants / Total</div><div class="stat-value">$(format_number "$total_variants")</div></div>
        <div class="stat-card variants"><div class="stat-label">Variants / PASS</div><div class="stat-value">$(format_number "$pass_variants")</div></div>
        <div class="stat-card highlighted"><div class="stat-label">Variants / Highlighted</div><div class="stat-value">$(format_number "$highlighted_count")</div></div>
        <div class="stat-card deletions"><div class="stat-label">Deletions / Total</div><div class="stat-value">$(format_number "$deletions_total")</div></div>
        <div class="stat-card highlighted"><div class="stat-label">Deletions / Highlighted</div><div class="stat-value">$(format_number "$deletions_highlighted")</div></div>
      </div>
    </div>
    <div class="section">
      <h2>Haplogroup</h2>
      $(
        haplo_raw="$sample_dir/haplo/${sample}-haplocheck.raw.txt"
        if [ -f "$haplo_raw" ]; then
          # Create temp file with quotes removed (preserve tabs)
          tmp_haplo=$(mktemp)
          sed 's/"//g' "$haplo_raw" > "$tmp_haplo"
          # Strict TSV to HTML rendering via Python (CSV with tab delimiter)
          python3 - "$tmp_haplo" << 'PY'
import html, csv, sys
from pathlib import Path
p = Path(sys.argv[1])
rows = []
with p.open(newline='') as f:
    rows = list(csv.reader(f, delimiter='\t'))
print('<table>')
if rows:
    # Replace "Contamination Status" header with just "Contamination" (column 2, index 1)
    headers = rows[0]
    if len(headers) > 1 and 'contamination status' in headers[1].lower():
        headers[1] = 'Contamination'
    print('<thead><tr>' + ''.join(f'<th>{html.escape(h)}</th>' for h in headers) + '</tr></thead>')
    print('<tbody>')
    for r in rows[1:]:
        row_html = '<tr>'
        for col_idx, c in enumerate(r):
            # Color code Contamination column (index 1): NO=green, YES=red, ND/other=orange
            if col_idx == 1:  # Contamination column
                val = c.strip().upper()
                if val == 'NO':
                    row_html += f'<td style="color:#155724; font-weight:bold;">{html.escape(c)}</td>'
                elif val == 'YES':
                    row_html += f'<td style="color:#721c24; font-weight:bold;">{html.escape(c)}</td>'
                else:  # ND or other
                    row_html += f'<td style="color:#856404; font-weight:bold;">{html.escape(c)}</td>'
            else:
                row_html += f'<td>{html.escape(c)}</td>'
        row_html += '</tr>'
        print(row_html)
    print('</tbody>')
print('</table>')
PY
          rm -f "$tmp_haplo"
        else
          echo "<p>Haplocheck file not found: ${sample}-haplocheck.raw.txt</p>"
        fi
      )
    </div>
    <div class="section">
      <h2>Variants</h2>
      <input type="checkbox" id="passOnly" class="pass-toggle">
      <label for="passOnly" class="filter-toggle"><span id="filterLabel">Show PASS only</span></label>
      $(
        if [ -f "$ann_tsv" ]; then
          # Use existing TSV file directly (already has all columns including HPL)
          # Note: DEL enrichment with END/SVLEN temporarily disabled to avoid compute node requirement
          tsv_to_html_table "$ann_tsv" "disease" "variants-table" "$ann_vcf"
        else
          echo "<p>Variant TSV not found: $(sanitize_html "$ann_tsv")</p>"
        fi
      )
    </div>
    <div class="section">
      <h2>Deletions</h2>
      $(
        del_file="$sample_dir/varcall/${sample}.baldur_del.txt"
        if [ -f "$del_file" ]; then
          # Count deletions; normalize whitespace/newlines to avoid arithmetic errors
          del_count=$(grep -vcE '^(#|$)' "$del_file" 2>/dev/null || echo "0")
          del_count=$(printf '%s' "$del_count" | head -n1 | tr -d '[:space:]')
          if [ "$del_count" -gt 0 ]; then
            echo '<table class="deletions-table">'
            echo '<thead><tr><th>Start</th><th>Stop</th><th>Strand</th><th>Length</th><th>Type</th><th>Count</th></tr></thead>'
            echo '<tbody>'
            
            tmp_rows=$(mktemp)
            awk 'BEGIN{FS="\t"; OFS="\t"} \
                 !/^#/ && NF>=3 { \
                   a=$1+0; b=$2+0; s=$3; \
                   t=(NF>=5?$5:""); c=(NF>=6?$6:0); \
                   if (a==0 && b==0) next; \
                   start=(a<b?a:b); stop=(a<b?b:a); len=stop-start; \
                   if (len<0) len=-len; \
                   if (c=="" || c!~ /^[0-9]+$/) c=0; \
                   print start, stop, s, len, t, c \
                 }' "$del_file" \
              | sort -t $'\t' -k1,1n -k2,2n -k3,3 \
              > "$tmp_rows"

            tmp_dedup=$(mktemp)
            awk 'BEGIN{FS=OFS="\t"} \
                 { \
                   start=$1; stop=$2; strand=$3; len=$4; t=$5; c=$6+0; \
                   key=start OFS stop; \
                   if (!(key in seen)) { \
                     seen[key]=1; splus[key]=0; sminus[key]=0; sumc[key]=0; ty[key]=t; l[key]=len; order[++n]=key; \
                   } \
                   if (strand=="+") splus[key]=1; else if (strand=="-") sminus[key]=1; \
                   sumc[key]+=c; if (ty[key]=="" && t!="") ty[key]=t; \
                 } \
                 END { \
                   for (i=1;i<=n;i++) { key=order[i]; \
                     strand=(splus[key]&&sminus[key]?"±":(splus[key]?"+":(sminus[key]?"-":"?"))); \
                     print key, strand, l[key], ty[key], sumc[key]; \
                   } \
                 }' "$tmp_rows" > "$tmp_dedup"

            while IFS=$'\t' read -r start stop strand length dtype count; do
              [ -z "$start" ] && continue
              start_esc=$(sanitize_html "$start")
              stop_esc=$(sanitize_html "$stop")
              strand_esc=$(sanitize_html "$strand")
              length_esc=$(sanitize_html "$length")
              dtype_esc=$(sanitize_html "${dtype:-}")
              count_esc=$(sanitize_html "$count")
              echo "<tr><td>$start_esc</td><td>$stop_esc</td><td>$strand_esc</td><td>$length_esc</td><td>$dtype_esc</td><td>$count_esc</td></tr>"
            done < "$tmp_dedup"
            rm -f "$tmp_rows" "$tmp_dedup"
            
            echo '</tbody></table>'
          else
            echo "<p>No deletions detected.</p>"
          fi
        else
          echo "<p>No deletions file found.</p>"
        fi
      )
    </div>
    <div class="section">
      <h2>Output files</h2>
      <div class="file-list">
        $(
          # Store variables before they go out of scope in subshell
          _sample_dir="$sample_dir"
          _sample="$sample"
          
          report_file="report-${_sample}.html"
          bam_file="${_sample}.chrM.sup,5mC_5hmC,6mA.sorted.bam"
          # If model suffix differs, pick the first available sorted BAM
          if [ ! -f "$_sample_dir/$bam_file" ]; then
            bam_found=$(find "$_sample_dir" -maxdepth 1 -type f -name "*.sorted.bam" | head -1 || true)
            if [ -n "$bam_found" ]; then
              bam_file=$(basename "$bam_found")
            else
              bam_file=""
            fi
          fi
          ann_vcf="${_sample}.ann.vcf"
          ann_tsv_file="${_sample}.ann.tsv"
          
          if [ -f "$_sample_dir/$report_file" ]; then
            report_size=$(du -h "$_sample_dir/$report_file" 2>/dev/null | cut -f1 || echo "?")
            echo "<div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $report_file ($report_size)</div>"
          else
            echo "<div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $report_file - NOT FOUND</div>"
          fi
          
          if [ -n "$bam_file" ] && [ -f "$_sample_dir/$bam_file" ]; then
            bam_size=$(du -h "$_sample_dir/$bam_file" 2>/dev/null | cut -f1 || echo "?")
            echo "<div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $(basename "$bam_file") ($bam_size)</div>"
          else
            echo "<div class=\"file-item\"><span class=\"badge badge-error\">✗</span> *.sorted.bam - NOT FOUND</div>"
          fi
          
          if [ -f "$_sample_dir/$ann_vcf" ]; then
            vcf_size=$(du -h "$_sample_dir/$ann_vcf" 2>/dev/null | cut -f1 || echo "?")
            echo "<div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $ann_vcf ($vcf_size)</div>"
          else
            echo "<div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $ann_vcf - NOT FOUND</div>"
          fi
          
          if [ -f "$_sample_dir/$ann_tsv_file" ]; then
            tsv_size=$(du -h "$_sample_dir/$ann_tsv_file" 2>/dev/null | cut -f1 || echo "?")
            echo "<div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $ann_tsv_file ($tsv_size)</div>"
          else
            echo "<div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $ann_tsv_file - NOT FOUND</div>"
          fi
        )
      </div>
    </div>
    <div class="section">
      <h2>Parameters</h2>
      $(
        demultmt_script="$SCRIPT_DIR/wf-demultmt.sh"
        bchg_script="$SCRIPT_DIR/wf-bchg.sh"
        
        # Extract Dorado parameters from wf-bchg.sh script
        dorado_params="N/A"
        if [ -f "$bchg_script" ]; then
          # Extract the dorado basecaller command
          dorado_params=$(awk '/DORADO_BIN basecaller/,/> "\$BASECALL_BAM"/ {print}' "$bchg_script" | \
                         grep -oE '\-\-[a-z-]+' | \
                         tr '\n' ' ' | \
                         sed 's/ $//')
          # If empty, it means no extra parameters (just model and path)
          if [ -z "$dorado_params" ]; then
            dorado_params="--recursive"
          fi
        fi
        
        # Extract Baldur parameters from wf-demultmt.sh script
        baldur_params="N/A"
        if [ -f "$demultmt_script" ]; then
          # Extract the baldur command (multi-line with backslashes)
          baldur_params=$(awk '/BALDUR_BIN.*--mapq/,/"\$BAM_FILE"/ {print}' "$demultmt_script" | \
                         grep -oE '\-\-[a-z-]+\s+[0-9]+|\-\-[a-z-]+' | \
                         grep -v -E '(--reference|--output-prefix|--sample)' | \
                         tr '\n' ' ' | \
                         sed 's/ $//')
        fi
        
        # Extract Haplocheck parameters from wf-demultmt.sh script
        haplo_params="N/A"
        if [ -f "$demultmt_script" ]; then
          # Look for haplocheck command line
          haplo_line=$(grep -E '^haplocheck\s+--' "$demultmt_script" | head -1)
          if [ -n "$haplo_line" ]; then
            haplo_params=$(echo "$haplo_line" | grep -oE '\-\-[a-z-]+' | tr '\n' ' ' | sed 's/ $//')
          fi
        fi
        
        echo "<div class=\"dorado-params\">"
        echo "  <strong>Dorado:</strong> "
        echo "  <code>$dorado_params</code>"
        echo "</div>"
        echo "<div class=\"baldur-params\">"
        echo "  <strong>Baldur:</strong> "
        echo "  <code>$baldur_params</code>"
        echo "</div>"
        echo "<div class=\"haplocheck-params\">"
        echo "  <strong>Haplocheck:</strong> "
        echo "  <code>$haplo_params</code>"
        echo "</div>"
      )
    </div>
    <div class="section">
      <h2>Logs</h2>
      $(
        demultmt_err="$sample_dir/slurm-${sample}.demultmt.err"
        modmito_err="$sample_dir/slurm-${sample}.modmito.err"
        
        has_errors=0
        has_warnings=0
        
        echo "<div style=\"margin:10px 0;\">"
        
        # Check demultmt log
        if [ -f "$demultmt_err" ]; then
          err_lines=$(grep -i "error\|failed\|exception" "$demultmt_err" 2>/dev/null || true)
          warn_lines=$(grep -i "warning" "$demultmt_err" 2>/dev/null || true)
          
          if [ -n "$err_lines" ]; then
            has_errors=1
            echo "<div class=\"log-status error\">Errors in demultmt log:</div>"
            echo "<pre style=\"background:#f8d7da;padding:10px;border-radius:5px;font-size:11px;overflow-x:auto;\">$(sanitize_html "$err_lines")</pre>"
          fi
          
          if [ -n "$warn_lines" ]; then
            has_warnings=1
            echo "<div class=\"log-status warning\">Warnings in demultmt log:</div>"
            echo "<pre style=\"background:#fff3cd;padding:10px;border-radius:5px;font-size:11px;overflow-x:auto;\">$(sanitize_html "$warn_lines")</pre>"
          fi
        fi
        
        # Check modmito log
        if [ -f "$modmito_err" ]; then
          err_lines=$(grep -i "error\|failed\|exception" "$modmito_err" 2>/dev/null || true)
          warn_lines=$(grep -i "warning" "$modmito_err" 2>/dev/null || true)
          
          if [ -n "$err_lines" ]; then
            has_errors=1
            echo "<div class=\"log-status error\">Errors in modmito log:</div>"
            echo "<pre style=\"background:#f8d7da;padding:10px;border-radius:5px;font-size:11px;overflow-x:auto;\">$(sanitize_html "$err_lines")</pre>"
          fi
          
          if [ -n "$warn_lines" ]; then
            has_warnings=1
            echo "<div class=\"log-status warning\">Warnings in modmito log:</div>"
            echo "<pre style=\"background:#fff3cd;padding:10px;border-radius:5px;font-size:11px;overflow-x:auto;\">$(sanitize_html "$warn_lines")</pre>"
          fi
        fi
        
        if [ "$has_errors" -eq 0 ] && [ "$has_warnings" -eq 0 ]; then
          echo "<div class=\"log-status success\">No errors or warnings in logs</div>"
        fi
        
        echo "</div>"
      )
    </div>
  </div>
  <footer style="margin-top:30px; padding-top:20px; border-top:1px solid #ddd; text-align:center; font-size:11px; color:#7f8c8d;">
    Generated by <strong>Nanomito</strong> — Marc FERRE &lt;marc.ferre@univ-angers.fr&gt;
  </footer>
  <script>
    // Update filter label text when checkbox state changes (works on iOS)
    document.addEventListener('DOMContentLoaded', function() {
      const filterCheckbox = document.getElementById('passOnly');
      const filterLabel = document.getElementById('filterLabel');
      if (filterCheckbox && filterLabel) {
        function updateLabel() {
          filterLabel.textContent = filterCheckbox.checked ? 'Show all variants' : 'Show PASS only';
        }
        filterCheckbox.addEventListener('change', updateLabel);
        updateLabel();
      }
    });
  </script>
</body>
</html>
EOF
}

append_section() {
  local title="$1"
  append_html "<div class=\"section\">"
  append_html "  <div class=\"section-title\">$title</div>"
}

count_vcf_variants() {
  local vcf_file="$1"
  if [ ! -f "$vcf_file" ]; then
    echo "N/A"
    return
  fi
  awk '!/^#/ {c++} END{print c+0}' "$vcf_file"
}

count_vcf_pass_variants() {
  local vcf_file="$1"
  if [ ! -f "$vcf_file" ]; then
    echo "N/A"
    return
  fi
  awk '!/^#/ && $7=="PASS" {c++} END{print c+0}' "$vcf_file"
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
    # Format with commas for thousands (English format: 1,234,567)
    echo "$num" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta'
  else
    echo "$num"
  fi
}

# --- Reports-only mode execution ------------------------------------------
# If only reports are requested, generate per-sample HTML reports AND global report
if [ "$REPORTS_ONLY" = "true" ]; then
  log_info "Generating per-sample HTML reports (reports-only mode)"
  
  # Load Conda environment for bcftools if needed for report generation
  log_info "Loading Conda environment for annotation tools (bcftools)"
  set +u  # Temporarily disable unset variable check for conda
  if [ -f /local/env/envconda.sh ]; then
    # shellcheck disable=SC1091  # File only exists on HPC cluster
    . /local/env/envconda.sh 2>/dev/null || log_warning "Failed to source envconda.sh, conda may already be available"
  else
    log_warning "Conda init script not found at /local/env/envconda.sh"
  fi
  set -u  # Re-enable unset variable check
  conda activate "$ANNOTMT_ENV" || log_warning "Failed to activate ANNOTMT_ENV"
  
  DEMULT_SUMMARY="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
  if [ ! -f "$DEMULT_SUMMARY" ]; then
    DEMULT_SUMMARY=$(find "$PROCESS_DIR" -maxdepth 2 -type f -name "demult_summary*.tsv" | head -1 || true)
  fi
  if [ ! -f "$DEMULT_SUMMARY" ]; then
    DEMULT_SUMMARY=$(find "$PROCESS_DIR" -maxdepth 2 -type f -name "demult_summary*.tsv" | head -1 || true)
  fi
  HAPLOCHECK_SUMMARY="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"
  count=0
  for sample_dir in "$PROCESS_DIR"/*/ ; do
    [ -d "$sample_dir" ] || continue
    sample_dir="${sample_dir%/}"
    sample="$(basename "$sample_dir")"
    if [ -f "$sample_dir/NO_DATA.marker" ]; then
      log_info "Skipping $sample (NO_DATA.marker)"
      continue
    fi
    generate_sample_html_report "$sample_dir" "$sample" "$DEMULT_SUMMARY" "$HAPLOCHECK_SUMMARY"
    log_ok "Report generated: $sample_dir/report-$sample.html"
    count=$((count+1))
  done
  if [ $count -eq 0 ]; then
    log_err "No sample directories found in $PROCESS_DIR"
  fi
  log_ok "Reports-only mode completed. Generated $count report(s)."
  
  # Now generate global run report (continue to normal mode for report generation)
  log_info "Generating global run report..."
fi

# --- Normal finalize mode starts here -------------------------------------
if [ "$REPORTS_ONLY" != "true" ]; then
  log_info "Preparing comprehensive email summary: $EMAIL_BODY_FILE"
else
  log_info "Preparing global run report..."
fi

# --- Email Header ---------------------------------------------------------
start_html

# --- MERGE TEMPORARY SUMMARY FILES FROM PARALLEL JOBS ---------------------
# Each demultmt/modmito job writes to its own .tmp file to avoid locking issues
# Now that all jobs are complete, merge them into final summary files
log_info "Merging temporary summary files from parallel jobs..."

# Merge demult_summary files
DEMULT_TMP_FILES=("$PROCESS_DIR"/demult_summary."$RUN_ID".*.tmp)
if [ ${#DEMULT_TMP_FILES[@]} -gt 0 ] && [ -f "${DEMULT_TMP_FILES[0]}" ]; then
  DEMULT_SUMMARY="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
  {
    printf "Run id\tSample id\tReads generated\tReads aligned to reference\tReads aligned to chrM\tReads matching both\n"
    cat "${DEMULT_TMP_FILES[@]}" | grep -v "^Run id" | sort
  } > "$DEMULT_SUMMARY"
  rm -f "${DEMULT_TMP_FILES[@]}"
  log_ok "Merged demult_summary: $(wc -l < "$DEMULT_SUMMARY") lines"
fi

# Merge haplocheck_summary files
HPLCHK_TMP_FILES=("$PROCESS_DIR"/haplocheck_summary."$RUN_ID".*.tmp)
if [ ${#HPLCHK_TMP_FILES[@]} -gt 0 ] && [ -f "${HPLCHK_TMP_FILES[0]}" ]; then
  HAPLOCHECK_SUMMARY="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"
  {
    head -n1 "${HPLCHK_TMP_FILES[0]}"
    tail -q -n +2 "${HPLCHK_TMP_FILES[@]}" | sort
  } > "$HAPLOCHECK_SUMMARY" 2>/dev/null || true
  rm -f "${HPLCHK_TMP_FILES[@]}"
  [ -f "$HAPLOCHECK_SUMMARY" ] && log_ok "Merged haplocheck_summary: $(wc -l < "$HAPLOCHECK_SUMMARY") lines"
fi

# Merge workflow_summary files
WORKFLOW_TMP_FILES=("$PROCESS_DIR"/workflows_summary."$RUN_ID".*.tmp)
if [ ${#WORKFLOW_TMP_FILES[@]} -gt 0 ] && [ -f "${WORKFLOW_TMP_FILES[0]}" ]; then
  SUMMARY_TSV="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"
  {
    printf "Run id\tSample id\tWorkflow\tRuntime (hh:mm:ss)\n"
    cat "${WORKFLOW_TMP_FILES[@]}" | grep -v "^Run id" | sort
  } > "$SUMMARY_TSV"
  rm -f "${WORKFLOW_TMP_FILES[@]}"
  log_ok "Merged workflows_summary: $(wc -l < "$SUMMARY_TSV") lines"
fi

append_html "<div class=\"header\">"
append_html "  <h1>🧬 NANOMITO WORKFLOW COMPLETED</h1>"
append_html "  <div class=\"subtitle\">"
append_html "    Run ID: $RUN_ID<br>"
append_html "    Completed: $(date '+%Y-%m-%d %H:%M:%S')"
append_html "  </div>"
append_html "</div>"

# --- 0. PRE-FLIGHT CHECK (non-blocking) -----------------------------------
# Note: Use a dedicated variable to avoid overwriting SCRIPT_DIR which is needed for tool paths
CHECK_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK_SCRIPT="$CHECK_SCRIPT_DIR/tools/check_run_ready.sh"
if [ ! -x "$CHECK_SCRIPT" ]; then
  # Try parent directory layout if script is in repo root
  [ -x "$CHECK_SCRIPT_DIR/../tools/check_run_ready.sh" ] && CHECK_SCRIPT="$CHECK_SCRIPT_DIR/../tools/check_run_ready.sh"
fi
if [ -x "$CHECK_SCRIPT" ]; then
  append_section "PRE-FLIGHT CHECK"
  tmp_check=$(mktemp)
  # Run quietly; never fail the email generation
  if "$CHECK_SCRIPT" "$RUN_DIR" > "$tmp_check" 2>/dev/null; then :; else :; fi
  # Extract summary counts
  summary_line=$(grep -E "^Result: PASS=.*WARN=.*FAIL=.*$" "$tmp_check" || true)
  if [ -n "$summary_line" ]; then
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Summary</span>"
    append_html "    <span class=\"metric-value\">${summary_line#Result: }</span>"
    append_html "  </div>"
  fi
  # List WARN/FAIL lines for quick visibility
  warnfail=$(grep -E "^\[(WARN|FAIL)\]" "$tmp_check" || true)
  if [ -n "$warnfail" ]; then
    append_html "  <pre style=\"background:#fff8e1;border:1px solid #f0e1a1;padding:8px;white-space:pre-wrap;\">"
    while IFS= read -r l; do
      esc=${l//&/&amp;}; esc=${esc//</&lt;}; esc=${esc//>/&gt;}
      append_html "${esc}"
    done <<< "$warnfail"
    append_html "  </pre>"
  else
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-value success\">✓ No pre-flight warnings</span>"
    append_html "  </div>"
  fi
  rm -f "$tmp_check"
  append_html "</div>"
fi

# --- 1. WORKFLOW EXECUTION SUMMARY ----------------------------------------
append_section "WORKFLOW EXECUTION SUMMARY"

SUMMARY_TSV="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"
if [ -f "$SUMMARY_TSV" ]; then
  # Calculate total runtime (use process substitution to avoid subshell issue)
  total_seconds=0
  while IFS=$'\t' read -r line; do
    workflow=$(echo "$line" | awk -F'\t' '{print $3}')
    runtime=$(echo "$line" | awk -F'\t' '{print $4}')
    
    if [ "$workflow" != "Workflow" ] && [ -n "$runtime" ]; then
      # Convert hh:mm:ss to seconds
      IFS=: read -r hours minutes seconds <<< "$runtime"
      # Remove leading zeros and spaces, default to 0 if empty
      hours=${hours##*( )}; hours=${hours#0}; hours=${hours:-0}
      minutes=${minutes##*( )}; minutes=${minutes#0}; minutes=${minutes:-0}
      seconds=${seconds##*( )}; seconds=${seconds#0}; seconds=${seconds:-0}
      seconds_total=$((hours * 3600 + minutes * 60 + seconds))
      total_seconds=$((total_seconds + seconds_total))
    fi
  done < <(tail -n +2 "$SUMMARY_TSV")
  
  # Format total time
  total_hours=$((total_seconds / 3600))
  total_minutes=$(((total_seconds % 3600) / 60))
  total_secs=$((total_seconds % 60))
  
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-label\">Status</span>"
  append_html "    <span class=\"metric-value success\">✓ All jobs completed successfully</span>"
  append_html "  </div>"
  
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-label\">Total runtime</span>"
  printf -v runtime_str "%02d:%02d:%02d" "$total_hours" "$total_minutes" "$total_secs"
  append_html "    <span class=\"metric-value\">$runtime_str</span>"
  append_html "  </div>"
  
  append_html "  <table>"
  append_html "    <tr><th>Sample</th><th>Workflow</th><th>Runtime</th></tr>"
  
  # Use awk to properly parse TSV with empty fields
  tail -n +2 "$SUMMARY_TSV" | while IFS=$'\t' read -r line; do
    # Extract fields using awk to properly handle empty fields
    sample_id=$(echo "$line" | awk -F'\t' '{print $2}')
    workflow=$(echo "$line" | awk -F'\t' '{print $3}')
    runtime=$(echo "$line" | awk -F'\t' '{print $4}')
    
    # Display "NA" if sample_id is empty or equals "NA"
    if [ -z "$sample_id" ] || [ "$sample_id" = "NA" ]; then
      sample_display="NA"
    else
      sample_display="$sample_id"
      # Truncate long sample names
      if [ ${#sample_display} -gt 35 ]; then
        sample_display="${sample_display:0:32}..."
      fi
    fi
    # Normalize runtime formatting to HH:MM:SS with leading zeros
    if [ -n "$runtime" ]; then
      IFS=: read -r rh rm rs <<< "$runtime"
      # Remove leading zeros to avoid octal interpretation, default to 0 if empty
      rh=$((10#${rh:-0}))
      rm=$((10#${rm:-0}))
      rs=$((10#${rs:-0}))
      printf -v runtime_fmt "%02d:%02d:%02d" "$rh" "$rm" "$rs"
    else
      runtime_fmt="00:00:00"
    fi
    
    append_html "    <tr>"
    append_html "      <td>$sample_display</td>"
    append_html "      <td>$workflow</td>"
    append_html "      <td>$runtime_fmt</td>"
    append_html "    </tr>"
  done
  
  append_html "  </table>"
else
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value warning\">⚠ Workflow summary file not found</span>"
  append_html "  </div>"
fi

append_html "</div>"

# --- 2. SEQUENCING RUN METRICS --------------------------------------------
append_section "SEQUENCING RUN METRICS"

# Try to find report file (JSON is easiest to parse, fallback to others)
# Search deeper to include preprocessing subdirectories
REPORT_JSON=$(find "$RUN_DIR" -type f -name "report_*.json" 2>/dev/null | sort -r | head -1)
REPORT_MD=$(find "$RUN_DIR" -type f -name "report_*.md" 2>/dev/null | sort -r | head -1)

if [ -n "$REPORT_JSON" ] && [ -f "$REPORT_JSON" ]; then
  # Extract key metrics using Python for proper JSON parsing
  # Metrics are in acquisitions[-1].acquisition_run_info.yield_summary (MinKNOW/Dorado report format)
  metrics_output=$(python3 << PYEOF
import json
try:
    with open("$REPORT_JSON") as f:
        data = json.load(f)
    acq = data.get("acquisitions", [])
    if acq:
        ys = acq[-1].get("acquisition_run_info", {}).get("yield_summary", {})
        rc = str(ys.get("read_count", "N/A"))
        # Try to get total bases: prefer basecalled_bases, fallback to estimated_selected_bases
        tb = str(ys.get("basecalled_bases", ys.get("estimated_selected_bases", "N/A")))
        pb = str(ys.get("basecalled_pass_bases", "N/A"))
        pr = str(ys.get("basecalled_pass_read_count", "N/A"))
        print(f"{rc}|{tb}|{pb}|{pr}")
    else:
        print("N/A|N/A|N/A|N/A")
except Exception as e:
    print("N/A|N/A|N/A|N/A")
PYEOF
)
  
  read_count=$(echo "$metrics_output" | cut -d'|' -f1)
  total_bases=$(echo "$metrics_output" | cut -d'|' -f2)
  basecalled_pass_bases=$(echo "$metrics_output" | cut -d'|' -f3)
  basecalled_pass_read_count=$(echo "$metrics_output" | cut -d'|' -f4)
  
  # Debug log
  log_info "REPORT_JSON=$REPORT_JSON | read_count=$read_count | total_bases=$total_bases | pass_reads=$basecalled_pass_read_count | pass_bases=$basecalled_pass_bases"
  
  if [ "$read_count" != "N/A" ] && [ "$read_count" != "" ]; then
    reads_formatted=$(format_number "$read_count")
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Total reads</span>"
    append_html "    <span class=\"metric-value info\">$reads_formatted</span>"
    append_html "  </div>"
  fi
  
  if [ "$total_bases" != "N/A" ] && [ "$total_bases" != "" ] && [ "$total_bases" != "0" ]; then
    bases_formatted=$(format_number "$total_bases")
    # Convert to Gb
    if [[ "$total_bases" =~ ^[0-9]+$ ]]; then
      bases_gb=$(awk "BEGIN {printf \"%.2f\", $total_bases / 1000000000}")
      append_html "  <div class=\"metric-row\">"
      append_html "    <span class=\"metric-label\">Total bases</span>"
      append_html "    <span class=\"metric-value info\">$bases_formatted <span class=\"info\">($bases_gb Gb)</span></span>"
      append_html "  </div>"
    else
      append_html "  <div class=\"metric-row\">"
      append_html "    <span class=\"metric-label\">Total bases</span>"
      append_html "    <span class=\"metric-value info\">$bases_formatted</span>"
      append_html "  </div>"
    fi
  fi
  
  if [ "$basecalled_pass_read_count" != "N/A" ] && [ "$basecalled_pass_read_count" != "" ] && [ "$basecalled_pass_read_count" != "0" ]; then
    pass_reads_formatted=$(format_number "$basecalled_pass_read_count")
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Passed reads</span>"
    append_html "    <span class=\"metric-value success\">$pass_reads_formatted</span>"
    append_html "  </div>"
  fi
  
  if [ "$basecalled_pass_bases" != "N/A" ] && [ "$basecalled_pass_bases" != "" ] && [ "$basecalled_pass_bases" != "0" ]; then
    bases_formatted=$(format_number "$basecalled_pass_bases")
    # Convert to Gb
    if [[ "$basecalled_pass_bases" =~ ^[0-9]+$ ]]; then
      bases_gb=$(awk "BEGIN {printf \"%.2f\", $basecalled_pass_bases / 1000000000}")
      append_html "  <div class=\"metric-row\">"
      append_html "    <span class=\"metric-label\">Passed bases</span>"
      append_html "    <span class=\"metric-value success\">$bases_formatted <span class=\"info\">($bases_gb Gb)</span></span>"
      append_html "  </div>"
    else
      append_html "  <div class=\"metric-row\">"
      append_html "    <span class=\"metric-label\">Passed bases</span>"
      append_html "    <span class=\"metric-value\">$bases_formatted</span>"
      append_html "  </div>"
    fi
  fi
  
elif [ -n "$REPORT_MD" ] && [ -f "$REPORT_MD" ]; then
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value\">Report found: $(basename "$REPORT_MD")</span>"
  append_html "  </div>"
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value warning\">(Metrics extraction from Markdown not yet implemented)</span>"
  append_html "  </div>"
else
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value warning\">ℹ No report file found (report_*.json or report_*.md)</span>"
  append_html "  </div>"
fi

append_html "</div>"

# --- 3. PER-SAMPLE RESULTS ------------------------------------------------
append_section "PER-SAMPLE RESULTS"

DEMULT_SUMMARY="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
HAPLOCHECK_SUMMARY="$PROCESS_DIR/haplocheck_summary.$RUN_ID.tsv"

if [ ! -f "$DEMULT_SUMMARY" ]; then
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value warning\">⚠ Demultiplexing summary not found</span>"
  append_html "  </div>"
fi

if [ ! -f "$HAPLOCHECK_SUMMARY" ]; then
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-value warning\">⚠ Haplocheck summary not found</span>"
  append_html "  </div>"
fi

append_html "</div>"

# Process each sample directory
sample_count=0
for sample_dir in "$PROCESS_DIR"/*/ ; do
  [ -d "$sample_dir" ] || continue
  
  # Remove trailing slash from sample_dir
  sample_dir="${sample_dir%/}"
  sample=$(basename "$sample_dir")
  sample_count=$((sample_count + 1))
  
  append_html "<div class=\"sample-card\">"
  append_html "  <div class=\"sample-header\">📊 Sample: $sample</div>"
  
  # Check for NO_DATA marker file
  if [ -f "$sample_dir/NO_DATA.marker" ]; then
    append_html "  <div style=\"margin: 10px 0; padding: 15px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;\">"
    append_html "    <strong style=\"color: #856404;\">⚠️ NO DATA</strong>"
    append_html "    <p style=\"margin: 5px 0 0 0; color: #856404;\">This sample had no reads matching both patient and reference mitochondria. Analysis was skipped.</p>"
    append_html "  </div>"
    append_html "</div>"
    continue
  fi
  
  # Extract demultiplexing metrics
  if [ -f "$DEMULT_SUMMARY" ]; then
    chrM_reads=$(awk -v s="$sample" '$2==s {print $5}' "$DEMULT_SUMMARY")
    matching_both=$(awk -v s="$sample" '$2==s {print $6}' "$DEMULT_SUMMARY")
    
    if [ -n "$chrM_reads" ]; then
      append_html "  <div style=\"margin: 10px 0;\">"
      append_html "    <strong>Alignment</strong>"
      append_html "    <div class=\"metric-row\">"
      append_html "      <span class=\"metric-label\">chrM reads</span>"
      append_html "      <span class=\"metric-value\">$(format_number "$chrM_reads")</span>"
      append_html "    </div>"
      append_html "    <div class=\"metric-row\">"
      append_html "      <span class=\"metric-label\">Matching both</span>"
      append_html "      <span class=\"metric-value\">$(format_number "$matching_both")</span>"
      append_html "    </div>"
      append_html "  </div>"
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
      
      # Color code contamination status: NO=green, YES=red, ND/other=orange
      status_class="success"
      status_color="#155724"
      if [ "$(echo "$contamination_status" | tr '[:lower:]' '[:upper:]')" = "YES" ]; then
        status_class="error"
        status_color="#721c24"
      elif [ "$(echo "$contamination_status" | tr '[:lower:]' '[:upper:]')" != "NO" ]; then
        status_class="warning"
        status_color="#856404"
      fi
      
      append_html "  <div style=\"margin: 10px 0;\">"
      append_html "    <strong>Haplogroup</strong>"
      append_html "    <div class=\"metric-row\">"
      append_html "      <span class=\"metric-label\">Contamination</span>"
      append_html "      <span class=\"metric-value\" style=\"color:$status_color; font-weight:bold;\">$contamination_status</span>"
      append_html "    </div>"
      append_html "    <div class=\"metric-row\">"
      append_html "      <span class=\"metric-label\">Major</span>"
      append_html "      <span class=\"metric-value\">$major_haplogroup</span>"
      append_html "    </div>"
      
      if [ "$major_haplogroup" != "$minor_haplogroup" ] && [ -n "$minor_haplogroup" ]; then
        append_html "    <div class=\"metric-row\">"
        append_html "      <span class=\"metric-label\">Minor</span>"
        append_html "      <span class=\"metric-value\">$minor_haplogroup</span>"
        append_html "    </div>"
      fi
      append_html "  </div>"
    else
      append_html "  <div style=\"margin: 10px 0; padding: 10px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;\">"
      append_html "    <strong>⚠️ Haplogroup unavailable</strong>"
      append_html "    <p style=\"margin: 5px 0 0 0; color: #856404;\">No haplocheck entry found (possible empty VCF or skipped analysis).</p>"
      append_html "  </div>"
    fi
  fi
  
  # Count variants in VCF
  vcf_file="$sample_dir/${sample}.ann.vcf"
  if [ -f "$vcf_file" ]; then
    total_variants=$(count_vcf_variants "$vcf_file")
    pass_variants=$(count_vcf_pass_variants "$vcf_file")
    
    append_html "  <div style=\"margin: 10px 0;\">"
    append_html "    <strong>Variants</strong>"
    append_html "    <div class=\"metric-row\">"
    append_html "      <span class=\"metric-label\">Total</span>"
    append_html "      <span class=\"metric-value\">$total_variants</span>"
    append_html "    </div>"
    append_html "    <div class=\"metric-row\">"
    append_html "      <span class=\"metric-label\">PASS</span>"
    append_html "      <span class=\"metric-value success\">$pass_variants</span>"
    append_html "    </div>"
    append_html "  </div>"

    # Highlight empty variant sets to make downstream emptiness explicit
    if [ "$total_variants" = "0" ]; then
      append_html "  <div style=\"margin: 10px 0; padding: 10px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;\">"
      append_html "    <strong>⚠️ No variants detected</strong>"
      append_html "    <p style=\"margin: 5px 0 0 0; color: #856404;\">VCF is empty; annotation tables and haplogroup call may be absent.</p>"
      append_html "  </div>"
    fi
  fi
  
  # Display deletions from Baldur
  del_file="$sample_dir/varcall/${sample}.baldur_del.txt"
  if [ -f "$del_file" ]; then
    # Count deletions (skip header if present); strip whitespace/newlines to keep integer comparison safe
    # Use || true to prevent grep from causing script to exit when no matches found (with set -e)
    del_count=$(grep -vcE '^(#|$)' "$del_file" 2>/dev/null || echo "0")
    del_count=$(printf '%s' "$del_count" | head -n1 | tr -d '[:space:]')
    
    if [ "$del_count" -gt 0 ]; then
      append_html "  <div style=\"margin: 10px 0;\">"
      append_html "    <strong>Deletions</strong>"
      append_html "    <div class=\"metric-row\">"
      append_html "      <span class=\"metric-label\">Total</span>"
      append_html "      <span class=\"metric-value\">$del_count</span>"
      append_html "    </div>"
      append_html "  </div>"
    fi
  fi
  
  # Generate standalone per-sample HTML report before listing files
  generate_sample_html_report "$sample_dir" "$sample" "$DEMULT_SUMMARY" "$HAPLOCHECK_SUMMARY"
  log_info "Per-sample report generated: $sample_dir/report-$sample.html"

  # Check for important output files
  append_html "  <div style=\"margin: 10px 0;\">"
  append_html "    <strong>Output files</strong>"
  append_html "    <div class=\"file-list\">"
  
  report_file="report-${sample}.html"
  bam_file="${sample}.chrM.sup,5mC_5hmC,6mA.sorted.bam"
  if [ ! -f "$sample_dir/$bam_file" ]; then
    bam_found=$(find "$sample_dir" -maxdepth 1 -type f -name "*.sorted.bam" | head -1 || true)
    if [ -n "$bam_found" ]; then
      bam_file=$(basename "$bam_found")
    else
      bam_file=""
    fi
  fi
  ann_tsv="${sample}.ann.tsv"
  ann_vcf="${sample}.ann.vcf"
  
  if [ -f "$sample_dir/$report_file" ]; then
    report_size=$(du -h "$sample_dir/$report_file" 2>/dev/null | cut -f1 || echo "?")
    append_html "      <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $report_file ($report_size)</div>"
  else
    append_html "      <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $report_file - NOT FOUND</div>"
  fi
  
  if [ -n "$bam_file" ] && [ -f "$sample_dir/$bam_file" ]; then
    bam_size=$(du -h "$sample_dir/$bam_file" 2>/dev/null | cut -f1 || echo "?")
    append_html "      <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $(basename "$bam_file") ($bam_size)</div>"
  else
    append_html "      <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> *.sorted.bam - NOT FOUND</div>"
  fi
  
  if [ -f "$sample_dir/$ann_vcf" ]; then
    vcf_size=$(du -h "$sample_dir/$ann_vcf" 2>/dev/null | cut -f1 || echo "?")
    append_html "      <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $ann_vcf ($vcf_size)</div>"
  else
    append_html "      <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $ann_vcf - NOT FOUND</div>"
  fi
  
  if [ -f "$sample_dir/$ann_tsv" ]; then
    tsv_size=$(du -h "$sample_dir/$ann_tsv" 2>/dev/null | cut -f1 || echo "?")
    append_html "      <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> $ann_tsv ($tsv_size)</div>"
  else
    append_html "      <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> $ann_tsv - NOT FOUND</div>"
  fi
  
  append_html "    </div>"
  append_html "  </div>"
  
  # Check for errors in logs
  demultmt_err="$sample_dir/slurm-${sample}.demultmt.err"
  modmito_err="$sample_dir/slurm-${sample}.modmito.err"
  
  error_count=0
  if [ -f "$demultmt_err" ]; then
    demultmt_errors=$(grep -ci "error\|failed\|exception" "$demultmt_err" 2>/dev/null | head -1 || echo "0")
    # Simple numeric check - if it's a number, use it
    case "$demultmt_errors" in
      ''|*[!0-9]*) demultmt_errors=0 ;;
    esac
    error_count=$((error_count + demultmt_errors))
  fi
  if [ -f "$modmito_err" ]; then
    modmito_errors=$(grep -ci "error\|failed\|exception" "$modmito_err" 2>/dev/null | head -1 || echo "0")
    case "$modmito_errors" in
      ''|*[!0-9]*) modmito_errors=0 ;;
    esac
    error_count=$((error_count + modmito_errors))
  fi
  
  if [ $error_count -gt 0 ]; then
    append_html "  <div style=\"margin-top: 10px; padding: 10px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;\">"
    append_html "    <span class=\"warning\">⚠ $error_count potential error(s) found in logs</span><br>"
    append_html "    <small>Check: $demultmt_err<br>Check: $modmito_err</small>"
    append_html "  </div>"
  fi
  
  append_html "</div>"

done

if [ $sample_count -eq 0 ]; then
  append_html "<div class=\"sample-card\">"
  append_html "  <span class=\"warning\">⚠ No sample directories found in processing/</span>"
  append_html "</div>"
else
  append_html "<div style=\"text-align: center; margin: 20px 0; font-weight: 600; color: #667eea;\">"
  append_html "  Total samples processed: $sample_count"
  append_html "</div>"
fi

# --- 4. SUMMARY FILES LOCATION --------------------------------------------
append_section "SUMMARY FILES"

append_html "  <div class=\"metric-row\">"
append_html "    <span class=\"metric-label\">Main directory</span>"
append_html "    <span class=\"metric-value\" style=\"font-size: 12px;\">$RUN_DIR</span>"
append_html "  </div>"

append_html "  <div class=\"metric-row\">"
append_html "    <span class=\"metric-label\">Processing directory</span>"
append_html "    <span class=\"metric-value\" style=\"font-size: 12px;\">$PROCESS_DIR</span>"
append_html "  </div>"

append_html "  <div style=\"margin-top: 15px;\"><strong>Key summary files:</strong></div>"

if [ -f "$SUMMARY_TSV" ]; then
  summary_size=$(du -h "$SUMMARY_TSV" 2>/dev/null | cut -f1 || echo "?")
  append_html "  <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> workflows_summary.$RUN_ID.tsv ($summary_size)</div>"
else
  append_html "  <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> workflows_summary.$RUN_ID.tsv (not found)</div>"
fi

if [ -f "$DEMULT_SUMMARY" ]; then
  demult_size=$(du -h "$DEMULT_SUMMARY" 2>/dev/null | cut -f1 || echo "?")
  append_html "  <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> demult_summary.$RUN_ID.tsv ($demult_size)</div>"
else
  append_html "  <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> demult_summary.$RUN_ID.tsv (not found)</div>"
fi

if [ -f "$HAPLOCHECK_SUMMARY" ]; then
  haplocheck_size=$(du -h "$HAPLOCHECK_SUMMARY" 2>/dev/null | cut -f1 || echo "?")
  append_html "  <div class=\"file-item\"><span class=\"badge badge-ok\">✓</span> haplocheck_summary.$RUN_ID.tsv ($haplocheck_size)</div>"
else
  append_html "  <div class=\"file-item\"><span class=\"badge badge-error\">✗</span> haplocheck_summary.$RUN_ID.tsv (not found)</div>"
fi

append_html "</div>"

# --- 5. ARCHIVING SUMMARY -------------------------------------------------
ARCHIVING_SUMMARY="$PROCESS_DIR/archiving_summary.$RUN_ID.tsv"

if [ -f "$ARCHIVING_SUMMARY" ]; then
  append_section "ARCHIVING SUMMARY"
  
  # Read archiving info from TSV (skip header)
  archiving_line=$(tail -n 1 "$ARCHIVING_SUMMARY")
  archive_status=$(echo "$archiving_line" | awk -F'\t' '{print $1}')
  archive_dir=$(echo "$archiving_line" | awk -F'\t' '{print $2}')
  archive_size=$(echo "$archiving_line" | awk -F'\t' '{print $3}')
  archive_runtime=$(echo "$archiving_line" | awk -F'\t' '{print $4}')
  archive_error=$(echo "$archiving_line" | awk -F'\t' '{print $5}')
  
  # Display status
  if [ "$archive_status" = "success" ]; then
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Status</span>"
    append_html "    <span class=\"metric-value success\">✓ Archiving completed successfully</span>"
    append_html "  </div>"
  else
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Status</span>"
    append_html "    <span class=\"metric-value error\">✗ Archiving failed</span>"
    append_html "  </div>"
    
    if [ -n "$archive_error" ]; then
      append_html "  <div style=\"margin-top: 10px; padding: 10px; background-color: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;\">"
      append_html "    <strong>⚠ Error:</strong> $archive_error"
      append_html "  </div>"
    fi
  fi
  
  # Display archiving directory
  append_html "  <div class=\"metric-row\">"
  append_html "    <span class=\"metric-label\">Destination</span>"
  append_html "    <span class=\"metric-value\"><code>$archive_dir</code></span>"
  append_html "  </div>"
  
  # Display total size
  if [ "$archive_size" != "N/A" ] && [ -n "$archive_size" ]; then
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Total size</span>"
    append_html "    <span class=\"metric-value info\">$archive_size</span>"
    append_html "  </div>"
  fi
  
  # Display archiving runtime
  if [ -n "$archive_runtime" ]; then
    append_html "  <div class=\"metric-row\">"
    append_html "    <span class=\"metric-label\">Archiving duration</span>"
    append_html "    <span class=\"metric-value\">$archive_runtime</span>"
    append_html "  </div>"
  fi
  
  append_html "</div>"
fi

# --- 6. FOOTER ------------------------------------------------------------
append_html "<div class=\"footer\">"
append_html "  <strong>End of Nanomito Report</strong><br>"
append_html "  Details available in: <code>$PROCESS_DIR</code>"
append_html "</div>"

end_html

# --- Send email -----------------------------------------------------------
send_email() {
  local subject="$1"; shift
  local file="$1"; shift
  if command -v mail >/dev/null 2>&1; then
    mail -a "Content-Type: text/html; charset=UTF-8" -s "$subject" "$MAIL_TO" < "$file" || return 1
    return 0
  elif command -v mailx >/dev/null 2>&1; then
    mailx -a "Content-Type: text/html; charset=UTF-8" -s "$subject" "$MAIL_TO" < "$file" || return 1
    return 0
  elif command -v sendmail >/dev/null 2>&1; then
    {
      echo "To: $MAIL_TO"
      echo "Subject: $subject"
      echo "Content-Type: text/html; charset=UTF-8"
      echo "MIME-Version: 1.0"
      echo
      cat "$file"
    } | sendmail -t || return 1
    return 0
  else
    return 2
  fi
}

# --- 7. ARCHIVE REPORTS --------------------------------------------------
# Archive generated reports to PROJECTS_DIR if configured
if [ -n "${PROJECTS_DIR:-}" ] && [ -d "$PROJECTS_DIR" ]; then
  log_info "Archiving generated reports to $PROJECTS_DIR/$RUN_ID"
  
  ARCHIVE_REPORTS_DIR="$PROJECTS_DIR/$RUN_ID/processing"
  if [ ! -d "$ARCHIVE_REPORTS_DIR" ]; then
    mkdir -p "$ARCHIVE_REPORTS_DIR" || {
      log_err "Cannot create archive directory: $ARCHIVE_REPORTS_DIR"
      exit 1
    }
  fi
  
  # Archive global and per-sample reports (including nested reports in sample directories)
  ARCHIVE_OK=true
  CHECKSUM_FILE="$ARCHIVE_REPORTS_DIR/reports_checksum.$RUN_ID.txt"
  
  # Use find to locate all report*.html files in processing tree
  while IFS= read -r report; do
    if [ -f "$report" ]; then
      # Preserve directory structure for sample reports
      rel_path="${report#"$PROCESS_DIR"/}"
      target_dir="$ARCHIVE_REPORTS_DIR/$(dirname "$rel_path")"
      
      # Create subdirectory if needed (for sample reports)
      if [ "$(dirname "$rel_path")" != "." ]; then
        mkdir -p "$target_dir" 2>/dev/null || true
      fi
      
      if cp "$report" "$target_dir/" 2>/dev/null; then
        # Calculate and append checksum
        sha256sum "$report" >> "$CHECKSUM_FILE" 2>/dev/null || true
        log_ok "Archived: $rel_path"
      else
        log_err "Failed to archive: $report"
        ARCHIVE_OK=false
      fi
    fi
  done < <(find "$PROCESS_DIR" -name "report*.html" -type f)
  
  # Verify archive
  if [ "$ARCHIVE_OK" = true ] && [ -f "$CHECKSUM_FILE" ]; then
    log_info "Verifying archived reports..."
    if (cd "$ARCHIVE_REPORTS_DIR" && sha256sum -c "$CHECKSUM_FILE" >/dev/null 2>&1); then
      log_ok "Reports archive verified with checksums"
    else
      log_err "Archive verification failed (checksum mismatch)"
      ARCHIVE_OK=false
    fi
  fi
  
  if [ "$ARCHIVE_OK" = true ]; then
    log_ok "Reports successfully archived and verified"
  else
    log_err "Reports archiving encountered errors"
  fi
else
  log_info "PROJECTS_DIR not configured; skipping report archiving"
fi

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

if [ "$REPORTS_ONLY" = "true" ]; then
  log_ok "Reports-only mode: Global report generated at $EMAIL_BODY_FILE"
else
  log_ok "Finalize completed"
fi
