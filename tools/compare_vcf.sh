#!/bin/bash
VERSION='2025-11-17'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Description:
# This script compares VCF files generated from Nanopore and Illumina sequencing.
# It performs the following tasks
# 1. Annotates VCF files with MITOMAP and gnomAD databases
# 2. Compares variants between Nanopore and Illumina
# 3. Performs haplogroup analysis
# 4. Exports results in TSV format
#
# Usage:
#   ./tools/compare_vcf.sh /path/to/directory
# If no argument is provided, the current directory will be used by default.

# Constants and reference paths
readonly HAPLOCHECK_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/haplocheck/haplocheck.jar'   
readonly SNPSIFT_BIN='/Users/marcferre/Documents/Recherche/Projets/Nanomito/Apps/snpEff/SnpSift.jar'
readonly ANN_GNOMAD='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/gnomAD/gnomad.genomes.v3.1.sites.chrM.vcf'
readonly ANN_MITOMAP_DISEASE='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/disease-nosp.vcf'
readonly ANN_MITOMAP_POLYMORPHISMS='/Users/marcferre/Documents/Recherche/Projets/Nanomito/References/MITOMAP/polymorphisms.vcf'

# ANSI color codes (no change needed)
readonly COLOR_RESET='\033[0m'
readonly COLOR_GREEN='\033[0;32m'   # Info
readonly COLOR_YELLOW='\033[0;33m'  # Warning
readonly COLOR_RED='\033[0;31m'     # Error

# Enable strict error handling
set -euo pipefail

# --- Functions (in alphabetical order) ---
# Log function to handle colored output and logging
_log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="[$(date '+%F %T')]"
  local log_line="$timestamp [$level] $message"
  
  # Select color based on level
  local color=""
  case "$level" in
      INFO)    color="$COLOR_GREEN";;
      WARN)    color="$COLOR_YELLOW";;
      ERROR)   color="$COLOR_RED";;
  esac

  # Write to log file (plain text)
  if [[ -n "${LOGFILE:-}" ]]; then
      printf '%s\n' "$log_line" >> "$LOGFILE"
  fi

  # Write to terminal (with colors)
  if [[ -t 1 && -n "$color" ]]; then
      printf "${color}%s${COLOR_RESET}\n" "$log_line"
  else
      printf '%s\n' "$log_line"
  fi
}

annotate_vcf() {
    local input_vcf="$1"
    local output_vcf="$2"
    local tmp_vcf1="${output_vcf}.tmp1"
    local tmp_vcf2="${output_vcf}.tmp2"

    _log INFO "Annotating VCF file: '$input_vcf'"

    # Check input file
    check_file "$input_vcf" "Input VCF"

    # Annotate with MITOMAP Disease
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_DISEASE" "$input_vcf" > "$tmp_vcf1"; then
        handle_error "Failed to annotate with MITOMAP Disease"
    fi

    # Annotate with MITOMAP Polymorphisms
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_MITOMAP_POLYMORPHISMS" "$tmp_vcf1" > "$tmp_vcf2"; then
        rm -f "$tmp_vcf1"
        handle_error "Failed to annotate with MITOMAP Polymorphisms"
    fi

    # Annotate with gnomAD
    if ! java -jar "$SNPSIFT_BIN" annotate -v "$ANN_GNOMAD" "$tmp_vcf2" > "$output_vcf"; then
        rm -f "$tmp_vcf1" "$tmp_vcf2"
        handle_error "Failed to annotate with gnomAD"
    fi

    # Cleanup temporary files
    rm -f "$tmp_vcf1" "$tmp_vcf2"
    _log INFO "Annotation completed: '$output_vcf'"
}

check_dependencies() {
    _log INFO "Checking dependencies..."
    local dependencies=("bgzip" "tabix" "bcftools" "bedtools" "java")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            _log ERROR "Error: $cmd is not installed or not in PATH." >&2
            exit 1
        fi
    done
    _log INFO "All dependencies are installed."
}

check_file() {
    local file="$1"
    local type="$2"
    
    if [[ ! -f "$file" ]]; then
        handle_error "$type file not found: $file"
    fi
    if [[ ! -r "$file" ]]; then
        handle_error "$type file not readable: $file"
    fi
}

check_output_dir() {
    local dir="$1"
    local name="$2"
    if ! mkdir -p "$dir"; then
        handle_error "Failed to create $name directory: $dir"
    fi
}

generate_html_report() {
    local workdir="$1"
    local prefix="$2"
    local isec_dir="$3"
    local hplchk_dir="$4"
    local log_file="$5"
    local report_file="${workdir}/report-${prefix}.html"
    
    _log INFO "Generating HTML report: '$report_file'"
    
    # Count variants in TSV files (use xargs to trim whitespace and newlines)
    local count_0000
    local count_0001
    local count_0002
    local count_0003
    count_0000=$(tail -n +2 "${isec_dir}/0000.tsv" 2>/dev/null | wc -l | xargs)
    count_0001=$(tail -n +2 "${isec_dir}/0001.tsv" 2>/dev/null | wc -l | xargs)
    count_0002=$(tail -n +2 "${isec_dir}/0002.tsv" 2>/dev/null | wc -l | xargs)
    count_0003=$(tail -n +2 "${isec_dir}/0003.tsv" 2>/dev/null | wc -l | xargs)
    
    # Check for errors and warnings in log (count only actual timestamped log lines)
    # When the script is run with 'set -x' the shell trace ('+' lines) can be redirected
    # into the same logfile and contain the literal '[ERROR]' or '[WARN]' tokens.
    # To avoid counting those trace lines we only count lines that start with the
    # timestamp format produced by _log: '[YYYY-MM-DD HH:MM:SS] [LEVEL] ...'
    local error_count
    local warn_count
    error_count=$(grep -E -c '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[ERROR\]' "$log_file" 2>/dev/null || true)
    warn_count=$(grep -E -c '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\] \[WARN\]' "$log_file" 2>/dev/null || true)
    
    # Extract haplogroups from haplocheck summary (column 10: "Major Haplogroup")
    local haplogroup_nanopore
    local haplogroup_illumina
    haplogroup_nanopore=$(awk -F'\t' 'NR==2 {gsub(/"/, "", $10); print $10}' "${hplchk_dir}/haplocheck_summary.${prefix}.tsv" 2>/dev/null || echo "N/A")
    haplogroup_illumina=$(awk -F'\t' 'NR==3 {gsub(/"/, "", $10); print $10}' "${hplchk_dir}/haplocheck_summary.${prefix}.tsv" 2>/dev/null || echo "N/A")
    
    # Verify 0002 == 0003
    local count_match_text="Match OK"
    local count_match_class="success"
    if [[ "$count_0002" -ne "$count_0003" ]]; then
        count_match_text="Mismatch!"
        count_match_class="error"
    fi
    
    # Generate HTML
    cat > "$report_file" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VCF Comparison Report - SAMPLE_ID</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        header {
            border-bottom: 3px solid #2c3e50;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }
        h1 {
            color: #2c3e50;
            font-size: 2em;
            margin-bottom: 10px;
        }
        .meta {
            color: #7f8c8d;
            font-size: 0.9em;
        }
        .summary {
            background: #ecf0f1;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
        }
        .summary h2 {
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.5em;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 15px;
        }
        .stat-card {
            background: white;
            padding: 15px;
            border-radius: 5px;
            border-left: 4px solid #3498db;
        }
        .stat-card.nanopore { border-left-color: #3498db; }
        .stat-card.illumina { border-left-color: #ff9800; }
        .stat-card.shared { border-left-color: #e74c3c; }
        .stat-card.haplogroup { border-left-color: #9b59b6; }
        .stat-card.total { border-left-color: #95a5a6; }
        .stat-label {
            font-size: 0.85em;
            color: #7f8c8d;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        .stat-value {
            font-size: 1.8em;
            font-weight: bold;
            color: #2c3e50;
        }
        .log-status {
            padding: 10px 15px;
            border-radius: 5px;
            font-weight: bold;
        }
        .log-status.success {
            background: #d4edda;
            color: #155724;
        }
        .log-status.warning {
            background: #fff3cd;
            color: #856404;
        }
        .log-status.error {
            background: #f8d7da;
            color: #721c24;
        }
        .section {
            margin-bottom: 40px;
        }
        .section h2 {
            color: #2c3e50;
            font-size: 1.5em;
            margin-bottom: 10px;
            padding-bottom: 10px;
            border-bottom: 2px solid #ecf0f1;
        }
        .section h3 {
            color: #34495e;
            font-size: 1.2em;
            margin: 20px 0 10px 0;
        }
        .table-description {
            color: #7f8c8d;
            font-size: 0.9em;
            margin-bottom: 10px;
            font-style: italic;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 20px;
            font-size: 0.85em;
            background: white;
        }
        thead {
            background: #34495e;
            color: white;
            position: sticky;
            top: 0;
        }
        th {
            padding: 12px 8px;
            text-align: left;
            font-weight: 600;
            border: 1px solid #2c3e50;
        }
        td {
            padding: 8px;
            border: 1px solid #ddd;
        }
        tbody tr:nth-child(even) {
            background: #f8f9fa;
        }
        tbody tr:hover {
            background: #e8f4f8;
        }
        tr.pathogenic {
            background-color: #ffebee !important;
        }
        tr.likely-pathogenic {
            background-color: #fff3e0 !important;
        }
        tr.benign {
            background-color: #fffde7 !important;
        }
        tr.deletion {
            background-color: #e6e6fa !important;
        }
        .table-wrapper {
            overflow-x: auto;
            margin-bottom: 30px;
        }
        footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 2px solid #ecf0f1;
            color: #7f8c8d;
            font-size: 0.85em;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>VCF Comparison Report</h1>
            <div class="meta">
                Sample: <strong>SAMPLE_ID</strong> | 
                Generated: <strong>GENERATION_DATE</strong> | 
                Script: compare_vcf v.SCRIPT_VERSION
            </div>
        </header>

        <div class="summary">
            <h2>Summary</h2>
            <div class="stats-grid">
                <div class="stat-card nanopore">
                    <div class="stat-label">Nanopore-only</div>
                    <div class="stat-value">COUNT_0000</div>
                </div>
                <div class="stat-card illumina">
                    <div class="stat-label">Illumina-only</div>
                    <div class="stat-value">COUNT_0001</div>
                </div>
                <div class="stat-card shared">
                    <div class="stat-label">Shared Variants</div>
                    <div class="stat-value">COUNT_0002</div>
                </div>
                <div class="stat-card total">
                    <div class="stat-label">Total Nanopore</div>
                    <div class="stat-value">TOTAL_NANOPORE</div>
                </div>
                <div class="stat-card total">
                    <div class="stat-label">Total Illumina</div>
                    <div class="stat-value">TOTAL_ILLUMINA</div>
                </div>
                <div class="stat-card shared">
                    <div class="stat-label">Highlighted Lines</div>
                    <div class="stat-value">HIGHLIGHTED_COUNT</div>
                </div>
                <div class="stat-card haplogroup">
                    <div class="stat-label">Haplogroup Nanopore</div>
                    <div class="stat-value">HAPLOGROUP_NANOPORE</div>
                </div>
                <div class="stat-card haplogroup">
                    <div class="stat-label">Haplogroup Illumina</div>
                    <div class="stat-value">HAPLOGROUP_ILLUMINA</div>
                </div>
            </div>
            <div class="log-status LOG_STATUS_CLASS">
                LOG_STATUS_MESSAGE
            </div>
            <div style="margin-top: 10px; padding: 10px; background: white; border-radius: 5px;">
                <strong>Shared variants check (0002 vs 0003):</strong> 
                <span class="LOG_MATCH_CLASS">COUNT_MATCH_STATUS</span>
            </div>
        </div>

        <div class="section">
            <h2>Haplogroup & Variant Analysis</h2>
            
            <h3>Haplogroup Comparison</h3>
            <div class="table-wrapper">
                HAPLOCHECK_TABLE
            </div>

            <h3>Nanopore-only Variants</h3>
            <div class="table-description">Variants found only in Nanopore sequencing</div>
            <div class="table-wrapper">
                TABLE_0000
            </div>

            <h3>Illumina-only Variants</h3>
            <div class="table-description">Variants found only in Illumina sequencing</div>
            <div class="table-wrapper">
                TABLE_0001
            </div>

            <h3>Shared Variants (Nanopore format)</h3>
            <div class="table-description">Variants present in both sequencing methods (Nanopore VCF format)</div>
            <div class="table-wrapper">
                TABLE_0002
            </div>

            <h3>Shared Variants (Illumina format)</h3>
            <div class="table-description">Variants present in both sequencing methods (Illumina VCF format)</div>
            <div class="table-wrapper">
                TABLE_0003
            </div>
        </div>

        <footer>
            Generated by compare_vcf v.SCRIPT_VERSION | Marc FERRE &lt;marc.ferre@univ-angers.fr&gt;
        </footer>
    </div>
</body>
</html>
EOF

    # Replace placeholders
    local total_nanopore=$((count_0000 + count_0002))
    local total_illumina=$((count_0001 + count_0003))
    local total_variants=$((count_0000 + count_0001 + count_0002))
    local highlighted_count
    highlighted_count=$(awk 'NR>1 && ($10 ~ /Cfrm-\[P\]/ || $10 ~ /Cfrm-\[LP\]/ || $10 ~ /Cfrm-\[B\]/ || $5 ~ /^<DEL/) {count++} END {print count+0}' "${isec_dir}/0000.tsv" "${isec_dir}/0001.tsv" "${isec_dir}/0002.tsv" 2>/dev/null || echo 0)
    local log_status_class="success"
    local log_status_msg="No errors or warnings"
    
    if [[ $error_count -gt 0 ]] || [[ $warn_count -gt 0 ]]; then
        log_status_class="warning"
        log_status_msg="$error_count error(s), $warn_count warning(s) found in logs"
    fi
    if [[ $error_count -gt 0 ]]; then
        log_status_class="error"
    fi
    
    # Use simpler markers for count_match
    local count_match_text="Match OK"
    if [[ "$count_0002" -ne "$count_0003" ]]; then
        count_match_text="Mismatch!"
        count_match_class="error"
    fi
    
    sed -i '' \
        -e "s/SAMPLE_ID/${prefix}/g" \
        -e "s/GENERATION_DATE/$(date '+%Y-%m-%d %H:%M:%S')/g" \
        -e "s/SCRIPT_VERSION/${VERSION}/g" \
        -e "s/COUNT_0000/${count_0000}/g" \
        -e "s/COUNT_0001/${count_0001}/g" \
        -e "s/COUNT_0002/${count_0002}/g" \
        -e "s/TOTAL_NANOPORE/${total_nanopore}/g" \
        -e "s/TOTAL_ILLUMINA/${total_illumina}/g" \
        -e "s/TOTAL_VARIANTS/${total_variants}/g" \
        -e "s/HIGHLIGHTED_COUNT/${highlighted_count}/g" \
        -e "s/HAPLOGROUP_NANOPORE/${haplogroup_nanopore}/g" \
        -e "s/HAPLOGROUP_ILLUMINA/${haplogroup_illumina}/g" \
        -e "s/LOG_STATUS_CLASS/${log_status_class}/g" \
        -e "s/LOG_STATUS_MESSAGE/${log_status_msg}/g" \
        -e "s/LOG_MATCH_CLASS/${count_match_class}/g" \
        -e "s/COUNT_MATCH_STATUS/${count_match_text}/g" \
        "$report_file"
    
    # Generate tables
    local haplocheck_html
    local table_0000_html
    local table_0001_html
    local table_0002_html
    local table_0003_html
    haplocheck_html=$(tsv_to_html "${hplchk_dir}/haplocheck_summary.${prefix}.tsv" "none")
    table_0000_html=$(tsv_to_html "${isec_dir}/0000.tsv" "disease")
    table_0001_html=$(tsv_to_html "${isec_dir}/0001.tsv" "disease")
    table_0002_html=$(tsv_to_html "${isec_dir}/0002.tsv" "disease")
    table_0003_html=$(tsv_to_html "${isec_dir}/0003.tsv" "disease")
    
    # Write tables to temp files
    echo "$haplocheck_html" > "$WORKDIR/haplocheck.html"
    echo "$table_0000_html" > "$WORKDIR/table_0000.html"
    echo "$table_0001_html" > "$WORKDIR/table_0001.html"
    echo "$table_0002_html" > "$WORKDIR/table_0002.html"
    echo "$table_0003_html" > "$WORKDIR/table_0003.html"
    
    # Replace table placeholders using sed
    sed -i '' '/HAPLOCHECK_TABLE/ {
r '"$WORKDIR/haplocheck.html"'
d
}' "$report_file"
    sed -i '' '/TABLE_0000/ {
r '"$WORKDIR/table_0000.html"'
d
}' "$report_file"
    sed -i '' '/TABLE_0001/ {
r '"$WORKDIR/table_0001.html"'
d
}' "$report_file"
    sed -i '' '/TABLE_0002/ {
r '"$WORKDIR/table_0002.html"'
d
}' "$report_file"
    sed -i '' '/TABLE_0003/ {
r '"$WORKDIR/table_0003.html"'
d
}' "$report_file"
    
    # Clean up temp files
    rm -f "$WORKDIR/haplocheck.html" "$WORKDIR/table_0000.html" "$WORKDIR/table_0001.html" "$WORKDIR/table_0002.html" "$WORKDIR/table_0003.html"
    
    _log INFO "HTML report generated successfully: '$report_file'"
}

tsv_to_html() {
    local tsv_file="$1"
    local coloring="$2"  # "disease" or "none"
    
    if [[ ! -f "$tsv_file" ]]; then
        echo "<p>File not found: $tsv_file</p>"
        return
    fi
    
    local html="<table>"
    local line_num=0
    
    while IFS=$'\t' read -r line; do
        line_num=$((line_num + 1))
        
        if [[ $line_num -eq 1 ]]; then
            # Header row
            html+="<thead><tr>"
            IFS=$'\t' read -ra headers <<< "$line"
            for header in "${headers[@]}"; do
                # Remove quotes
                header="${header//\"/}"
                html+="<th>${header}</th>"
            done
            html+="</tr></thead><tbody>"
        else
            # Data row - check for disease status
            IFS=$'\t' read -ra fields <<< "$line"
            local row_class=""
            if [[ "$coloring" == "disease" ]]; then
                # Check for DiseaseStatus values in TSV columns
                # DiseaseStatus may contain multiple comma-separated tags
                # e.g. "Cfrm-[P],Cfrm-[LP]" — accept P/LP/B followed by comma, tab or EOL
                if echo "$line" | grep -qE '\tCfrm-\[P\](,|\t|$)'; then
                    row_class=' class="pathogenic"'
                elif echo "$line" | grep -qE '\tCfrm-\[LP\](,|\t|$)'; then
                    row_class=' class="likely-pathogenic"'
                elif echo "$line" | grep -qE '\tCfrm-\[B\](,|\t|$)'; then
                    row_class=' class="benign"'
                fi
            fi
            if [[ "${fields[4]}" =~ ^"<DEL" ]]; then
                row_class=' class="deletion"'$row_class
            fi
            
            html+="<tr${row_class}>"
            local col=0
            for field in "${fields[@]}"; do
                # Remove quotes and escape HTML
                field="${field//\"/}"
                field="${field//&/&amp;}"
                field="${field//</&lt;}"
                field="${field//>/&gt;}"
                html+="<td>${field}</td>"
                ((col++))
            done
            html+="</tr>"
        fi
    done < "$tsv_file"
    
    html+="</tbody></table>"
    echo "$html"
}

clean_vcf() {
    local input_vcf="$1"
    local output_vcf="$2"
    local issues_found=0
    
    _log INFO "Validating and cleaning VCF file: '$input_vcf'"
    
    # Read header and data separately
    local header_lines=0
    local total_lines=0
    local malformed_lines=0
    
    # First pass: detect issues
    while IFS= read -r line; do
        total_lines=$((total_lines + 1))
        
        # Skip header lines
        if [[ "$line" =~ ^# ]]; then
            header_lines=$((header_lines + 1))
            continue
        fi
        
        # Check data lines for malformed FORMAT fields
        IFS=$'\t' read -ra fields <<< "$line"
        
        # VCF should have at least 8 columns (up to INFO)
        # If header has FORMAT column (9 fields), data lines should have sample data (10 fields)
        # If data line has exactly 9 columns, it's malformed (FORMAT but no sample)
        if [[ ${#fields[@]} -eq 9 ]]; then
            # FORMAT column present but no sample data - malformed
            malformed_lines=$((malformed_lines + 1))
            issues_found=1
            _log WARN "Malformed line at position ${fields[1]}: FORMAT defined but no sample data (9 fields instead of 10)"
        fi
    done < "$input_vcf"
    
    if [[ $issues_found -eq 0 ]]; then
        _log INFO "VCF validation passed: no issues found"
        # Just copy the file
        cp "$input_vcf" "$output_vcf"
        return 0
    fi
    
    _log WARN "Found $malformed_lines malformed line(s) in VCF - cleaning..."
    
    # Second pass: clean the file (remove malformed lines entirely)
    local removed_count=0
    {
        while IFS= read -r line; do
            # Copy all header lines as-is
            if [[ "$line" =~ ^# ]]; then
                echo "$line"
                continue
            fi
            
            # Process data lines
            IFS=$'\t' read -ra fields <<< "$line"
            
            # Skip lines with exactly 9 fields (FORMAT but no sample data)
            if [[ ${#fields[@]} -eq 9 ]]; then
                ((removed_count++))
                continue
            fi
            
            # Keep all other lines
            echo "$line"
        done < "$input_vcf"
    } > "$output_vcf"
    
    _log INFO "Removed $removed_count malformed line(s) from VCF"
    
    _log INFO "VCF cleaning completed: '$output_vcf'"
    return 0
}

cleanup_compressed_files() {
    local vcf_file="$1"
    _log INFO "Decompressing and cleaning up: '$vcf_file'"
    bgzip -d -f "${vcf_file}.gz"
    rm -f "${vcf_file}.gz.tbi"
}

cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        _log ERROR "Script failed with errors. Check the log file for details: $LOGFILE"
    fi
    
    # Cleanup temporary files
    cleanup_compressed_files "$VCF_NANOPORE"
    cleanup_compressed_files "$VCF_ILLUMINA_ANNOTMT"
    
    local files_to_remove=("$VCF_ILLUMINA_ANNOTMT" "$VCF_NANOPORE_PASS" "$VCF_ILLUMINA_CLEAN")
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                _log INFO "Removed temporary file: '$file'"
            else
                _log WARN "Warning: Failed to remove temporary file: '$file'" >&2
            fi
        fi
    done
}

compress_and_index() {
    local vcf_file="$1"
    _log INFO "Compressing and indexing: '$vcf_file'"
    bgzip -f "$vcf_file"
    tabix -p vcf -f "${vcf_file}.gz"
}

create_directory() {
    local dir="$1"
    local dir_name="$2"
    
    if ! mkdir -p "$dir"; then
        handle_error "Failed to create $dir_name directory: $dir"
    fi
    _log INFO "Created '$dir_name' directory: '$dir'"
}

export_vcf_to_tsv_Illumina() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    _log INFO "Exporting VCF to TSV (Illumina): '$input_vcf' -> '$output_tsv'"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tQUAL\tDP" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %AF]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t%QUAL\t[ %DP]\n' "$input_vcf" >> "$output_tsv"

    _log INFO "TSV file generated: '$output_tsv'"
}

export_vcf_to_tsv_Nanopore() {
    local input_vcf="$1"
    local output_tsv="${input_vcf%.vcf}.tsv"

    _log INFO "Exporting VCF to TSV (Nanopore): '$input_vcf' -> '$output_tsv'"

    # Add header to the TSV file
    echo -e "CHROM\tPOS\tID\tREF\tALT\tHPL\tAC\tAF\tDisease\tDiseaseStatus\tHGFL\tPubmedIDs\taachange\theteroplasmy\thomoplasmy\tmitotip_trna_prediction\tmitotip_score\tAC_het\tAC_hom\tAF_het\tAF_hom\tAN\tfilters\thap_defining_variant\tmax_hl\tpon_ml_probability_of_pathogenicity\tpon_mt_trna_prediction\tFILTER\tADF\tADR\tQUAL\tDP\tEND\tSVLEN" > "$output_tsv"

    # Convert VCF to TSV using bcftools query
    bcftools query -f '%CHROM\t%POS\t%ID\t%REF\t%ALT\t[ %HPL]\t%AC\t%AF\t%Disease\t%DiseaseStatus\t%HGFL\t%PubmedIDs\t%aachange\t%heteroplasmy\t%homoplasmy\t%mitotip_trna_prediction\t%mitotip_score\t%AC_het\t%AC_hom\t%AF_het\t%AF_hom\t%AN\t%filters\t%hap_defining_variant\t%max_hl\t%pon_ml_probability_of_pathogenicity\t%pon_mt_trna_prediction\t%FILTER\t[ %ADF]\t[ %ADR]\t%QUAL\t%DP\t%INFO/END\t%INFO/SVLEN\n' "$input_vcf" >> "$output_tsv"

    # Modify ALT for deletions
    awk 'BEGIN{FS=OFS="\t"} NR>1 && $5 == "<DEL>" { $5 = "<DEL:END=" $(NF-1) ";SVLEN=" $NF ">" } { print }' "$output_tsv" > "${output_tsv}.tmp" && mv "${output_tsv}.tmp" "$output_tsv"

    _log INFO "TSV file generated: '$output_tsv'"
}

filter_pass_variants() {
    local vcf_file="$1"
    local output_file="$2"

    _log INFO "Filtering PASS variants from '$vcf_file'"

    if ! bcftools view -f PASS "$vcf_file" > "$output_file"; then
        handle_error "Failed to filter PASS variants"
    fi

    _log INFO "PASS variants filtered to '$output_file'"
}

find_vcf_files() {
    local dir="$1"

    # Use find command for reliable file discovery
    local nanopore_file
    local illumina_file
    nanopore_file=$(find "$dir" -maxdepth 1 -name "*.ann.vcf" -print -quit)
    illumina_file=$(find "$dir" -maxdepth 1 -name "i---*.vcf" -print -quit)

    # Validate Nanopore file existence
    if [[ -z "$nanopore_file" ]]; then
        _log ERROR "Error: No Nanopore VCF file (*.ann.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    # Validate Illumina file existence
    if [[ -z "$illumina_file" ]]; then
        _log ERROR "Error: No Illumina VCF file (i---*.vcf) found in $dir" >&2
        ls -l "$dir" >&2
        exit 1
    fi

    # Display debug messages on stderr
    _log INFO "Found:" >&2
    _log INFO "- Nanopore: '$nanopore_file'" >&2
    _log INFO "- Illumina: '$illumina_file'" >&2

    # Return file paths on stdout
    printf "%s\n%s\n" "$nanopore_file" "$illumina_file"
}

handle_error() {
    local error_msg="$1"
    _log ERROR "$error_msg" >&2
    exit 1
}

is_file_readable() {
    local file="$1"
    [[ -f "$file" && -r "$file" ]]
}

print_summary() {
    local start_time="$1"
    local end_time="$2"
    local runtime=$((end_time - start_time))
    
    _log INFO "Summary:"
    _log INFO "- Input directory: '$WORKDIR'"
    _log INFO "- Log file: '$LOGFILE'"
    _log INFO "- Bcftools isec directory: '$ISEC_DIR'"
    _log INFO "- Haplocheck directory: '$HPLCHK_DIR'"
    _log INFO "- Execution time: $(printf '%02d:%02d:%02d' $((runtime/3600)) $((runtime%3600/60)) $((runtime%60)))"
}

process_haplocheck() {
    local vcf_file="$1"
    local summary_file="$2"
    local hplchk_dir="$3"
    
    _log INFO "Processing haplocheck for '$vcf_file'..."

    # Run Haplocheck
    prefix="${hplchk_dir}/hplchk_tmp"
    if ! java -jar "$HAPLOCHECK_BIN" --raw --out "$prefix" "$vcf_file"; then
        handle_error "haplocheck failed"
    fi
    
    # Update summary file
    local raw_file="${prefix}.raw.txt"
    if [[ ! -e "$summary_file" ]]; then
        cp "$raw_file" "$summary_file"
        _log INFO "File '$summary_file' created (with header)"
    else
        tail -n +2 "$raw_file" >> "$summary_file"
        _log INFO "Line added to '$summary_file'"
    fi

    # Cleanup files
    rm -f "$prefix" "${prefix}.html" "$raw_file"
    _log INFO "Haplocheck completed"
}

recreate_directory() {
  local DIR="$1"
  if [ -z "$DIR" ]; then
    _log ERROR "No directory specified."
    return 1
  fi

  if [ -d "$DIR" ]; then
    _log WARN "Directory '$DIR' exists. Removing..."
    rm -rf "$DIR"
    if [ ! -d "$DIR" ]; then
      _log INFO "Directory '$DIR' successfully removed."
    else
      _log ERROR "Failed to remove directory '$DIR'."
      return 1
    fi
  else
    _log INFO "Directory '$DIR' does not exist."
  fi

  _log INFO "Recreating directory '$DIR'..."
  mkdir -p "$DIR"
  if [ -d "$DIR" ]; then
    _log INFO "Directory '$DIR' successfully created."
  else
    _log ERROR "Failed to create directory '$DIR'."
    return 1
  fi
}

validate_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        handle_error "The specified directory '$dir' does not exist."
    fi
    if [[ ! -r "$dir" || ! -w "$dir" ]]; then
        handle_error "The specified directory '$dir' is not readable or writable."
    fi
}

validate_reference_files() {
    _log INFO "Checking reference files..."
    local ref_files=(
        "$SNPSIFT_BIN"
        "$ANN_GNOMAD"
        "$ANN_MITOMAP_DISEASE"
        "$ANN_MITOMAP_POLYMORPHISMS"
    )
    for ref in "${ref_files[@]}"; do
        if [[ ! -f "$ref" ]]; then
            _log ERROR "Error: Reference file not found: '$ref'" >&2
            exit 1
        fi
        if [[ ! -r "$ref" ]]; then
            _log ERROR "Error: Reference file not readable: '$ref'" >&2
            exit 1
        fi
    done
    _log INFO "All reference files are valid."
}

# --- Main function ---
main() {
    # Setup error handling and cleanup
    trap cleanup_on_exit EXIT
    trap 'handle_error "Script interrupted"' INT TERM

    # Start timing
    START=$(date +%s)

    # Initialize working directory and validate
    WORKDIR=$(cd "${1:-$(pwd)}" && pwd)
    validate_directory "$WORKDIR"
    
    # Extract prefix from directory name
    PREFIX=${WORKDIR##*/}
    PREFIX=${PREFIX:-/}

    # Create output directory for logs
    LOGDIR="$WORKDIR/logs"
    recreate_directory "$LOGDIR"

    # Setup logging without append
    LOGFILE="$LOGDIR/${PREFIX}-compare_vcf.log"
    exec > >(tee "$LOGFILE") 2>&1

    # Workflow information
    _log INFO "Tool: compare_vcf v.$VERSION by $AUTHOR"
    _log INFO "Date: $(LC_TIME=C date '+%b %d, %Y %H:%M:%S')"
    _log INFO "Sample: '$PREFIX'"
    _log INFO "Working directory: '$WORKDIR'"

    # Check dependencies and reference files
    check_dependencies
    validate_reference_files

    # Find VCF files with improved error handling
    local vcf_output
    vcf_output=$(find_vcf_files "$WORKDIR")
    
    # Create the table from the output (compatible with bash 3.2 macOS)
    VCF_FILES=()
    while IFS= read -r line; do
        VCF_FILES+=("$line")
    done <<< "$vcf_output"
    
    # Verifying the number of files found
    if [[ ${#VCF_FILES[@]} -ne 2 ]]; then
        _log ERROR "Error: Expected exactly 2 VCF files, found ${#VCF_FILES[@]}" >&2
        exit 1
    fi

    # Assigning found files (compatible with bash)
    VCF_NANOPORE="${VCF_FILES[0]}"
    VCF_ILLUMINA="${VCF_FILES[1]}"

    _log INFO '**********************'
    _log INFO '* VCF Validation     *'
    _log INFO '**********************'
    
    # Clean Illumina VCF (fix malformed lines)
    VCF_ILLUMINA_CLEAN="${VCF_ILLUMINA%.vcf}.clean.vcf"
    clean_vcf "$VCF_ILLUMINA" "$VCF_ILLUMINA_CLEAN"

    _log INFO '**********************'
    _log INFO '* Variant Annotation *'
    _log INFO '**********************'

    # Annotate cleaned Illumina VCF
    VCF_ILLUMINA_ANNOTMT="${VCF_ILLUMINA%.vcf}.ann.vcf"
    annotate_vcf "$VCF_ILLUMINA_CLEAN" "$VCF_ILLUMINA_ANNOTMT"

    _log INFO '******************'
    _log INFO '* PASS Filtering *'
    _log INFO '******************'
    VCF_NANOPORE_PASS="${VCF_NANOPORE%.vcf}.PASS.vcf"
    filter_pass_variants "$VCF_NANOPORE" "$VCF_NANOPORE_PASS"

    _log INFO '*************************'
    _log INFO '* Haplogroup Comparison *'
    _log INFO '*************************'

    HPLCHK_DIR="$WORKDIR/hplchk-${PREFIX}"
    HPLCHK_SUMMARY_FILE="${HPLCHK_DIR}/haplocheck_summary.${PREFIX}.tsv"
   
    # Create output directory for haplocheck
    recreate_directory "$HPLCHK_DIR"

    # Process haplocheck for Nanopore and Illumina
    _log INFO "Comparing haplogroups using haplocheck..."

    process_haplocheck "$VCF_NANOPORE_PASS" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"
    process_haplocheck "$VCF_ILLUMINA_ANNOTMT" "$HPLCHK_SUMMARY_FILE" "$HPLCHK_DIR"

    _log INFO '***********************'
    _log INFO '* Variants Comparison *'
    _log INFO '***********************'

    # Compress and index files
    compress_and_index "$VCF_NANOPORE"
    compress_and_index "$VCF_ILLUMINA_ANNOTMT"

    # Create output directory for bcftools isec
    ISEC_DIR="$WORKDIR/isec-$PREFIX"
    recreate_directory "$ISEC_DIR"

    # Compare VCF files using bcftools isec
    _log INFO "Comparing VCF files using bcftools isec..."
    if ! bcftools isec "${VCF_NANOPORE}.gz" "${VCF_ILLUMINA_ANNOTMT}.gz" --prefix "$ISEC_DIR" --apply-filters PASS; then
        _log ERROR "Error: bcftools isec failed" >&2
        exit 1
    fi
    
    # Export VCF files to TSV
    _log INFO '******************'
    _log INFO '* TSV Conversion *'
    _log INFO '******************'
    
    # Export specific VCF files in ISEC_DIR
    if [[ -d "$ISEC_DIR" ]]; then
        _log INFO "Converting specific VCF files to TSV in: '$ISEC_DIR'"
        for vcf_num in "0000" "0002"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Nanopore "$vcf_file"
            else
                _log WARN "Warning: File '$vcf_file' not found"
            fi
        done
    else
        _log WARN "Warning: Directory '$ISEC_DIR' not found. Skipping TSV conversion."
    fi

    if [[ -d "$ISEC_DIR" ]]; then
        _log INFO "Converting specific VCF files to TSV in: '$ISEC_DIR'"
        for vcf_num in "0001" "0003"; do
            vcf_file="$ISEC_DIR/$vcf_num.vcf"
            if [[ -f "$vcf_file" ]]; then
                export_vcf_to_tsv_Illumina "$vcf_file"
            else
                _log WARN "Warning: File '$vcf_file' not found"
            fi
        done
    else
        _log WARN "Warning: Directory $ISEC_DIR not found. Skipping TSV conversion."
    fi

    # Generate HTML report
    _log INFO '********************'
    _log INFO '* Generating Report *'
    _log INFO '********************'
    
    generate_html_report "$WORKDIR" "$PREFIX" "$ISEC_DIR" "$HPLCHK_DIR" "$LOGFILE"

    # Print final messages
    _log INFO '**********'
    _log INFO '* ENDING *'
    _log INFO '**********'

    # End timing
    END=$(date +%s)
    
    # Print summary
    print_summary "$START" "$END"
}

# Run the main function
main "$@"