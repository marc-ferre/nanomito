#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# export_results.sh - Export key result files from nanomito runs
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
#
# Version from git tags (fallback to 'unknown' if not in git repo)
# shellcheck disable=SC2034
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" describe --tags 2>/dev/null || echo 'unknown')"
#
# Description:
#   Copies analysis results (TSV, VCF, BAM, BAI files) from run directories
#   to ~/export/<run_id>
#
################################################################################
# USAGE
################################################################################
show_usage() {
    cat << EOF
Usage: $0 RUN_PATH [RUN_NAME]

Export analysis results from a run directory to export directory, organized by run and sample.

Arguments:
    RUN_PATH    Required. Path to the run directory to export
                (e.g., /path/to/workbench/run_dir)
    
    RUN_NAME    Optional. Name to use for the export directory and archive file.
                If not provided, uses the basename of RUN_PATH.

Examples:
    # Export with automatic name (uses basename)
    $0 /path/to/workbench/run_dir
    
    # Export with custom name
    $0 /path/to/workbench/run_dir my_custom_name

Output:
    Files are exported to: $EXPORT_BASE/<run_name>/<sample_id>/
    Archive created: $EXPORT_BASE/<run_name>.tar.gz

Exported files:
    - *.ann.tsv
    - *.ann.vcf
    - *.chrM.sup,5mC_5hmC,6mA.sorted.bam
    - *.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai
    - report-*.html
EOF
}
#
# Directory structure:
#   Source: <run_directory>/processing/<sample>/
#   Target: ~/export/<run>/<sample>/
#

set -euo pipefail

# Enable nullglob to handle patterns that don't match any files
shopt -s nullglob

# Configuration
EXPORT_DIR="$HOME/export"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Usage information
usage() {
    local error_msg="$1"
    
    if [ -n "$error_msg" ]; then
        echo ""
        log_error "$error_msg"
    fi
    
    cat << EOF

Usage: $0 RUN_PATH [RUN_NAME]

Export analysis results from a run directory to export directory.

Arguments:
  RUN_PATH    Required. Path to the run directory to export
              (e.g., /path/to/workbench/run_dir)

  RUN_NAME    Optional. Custom name to use for the export directory and archive file.
              If not provided, uses the basename of RUN_PATH.

Examples:
  # Export with automatic name (uses basename of path)
  $0 /path/to/workbench/run_dir

  # Export with custom name
  $0 /path/to/workbench/run_dir my_custom_export

Output:
  Files are exported to: $EXPORT_DIR/<run_name>/<sample_id>/
  Archive created: $EXPORT_DIR/<run_name>.zip (or .tar.gz if zip unavailable)

Exported files per sample:
  - *.ann.tsv
  - *.ann.vcf
  - *.chrM.sup,5mC_5hmC,6mA.sorted.bam
  - *.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai
  - report-*.html
EOF
    exit 0
}

# File patterns to export
FILE_PATTERNS=(
    "*.ann.tsv"
    "*.ann.vcf"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai"
    "report-*.html"
)

# Export files for a single sample
export_sample() {
    local sample_dir=$1
    local export_sample_dir=$2
    local sample_id
    sample_id=$(basename "$sample_dir")
    local file_count=0
    
    # Create export directory
    mkdir -p "$export_sample_dir"
    
    # Copy each file pattern
    for pattern in "${FILE_PATTERNS[@]}"; do
        for file in "$sample_dir"/$pattern; do
            if [ -f "$file" ]; then
                cp "$file" "$export_sample_dir/"
                file_count=$((file_count + 1))
            fi
        done
    done
    
    if [ $file_count -gt 0 ]; then
        log_success "  Sample $sample_id: $file_count file(s) exported"
        return 0
    else
        log_warning "  Sample $sample_id: no files found matching patterns"
        return 1
    fi
}

# Export all samples from a run
export_run() {
    local run_dir=$1
    local run_name=$2  # Optional custom name
    local run_id
    
    # Use custom name if provided, otherwise use basename
    if [ -n "$run_name" ]; then
        run_id="$run_name"
    else
        run_id=$(basename "$run_dir")
    fi
    
    local processing_dir="$run_dir/processing"
    local export_run_dir="$EXPORT_DIR/$run_id"
    
    echo ""
    log_info "Processing run: $run_id"
    log_info "Source: $processing_dir"
    log_info "Target: $export_run_dir"
    
    # Check if processing directory exists
    if [ ! -d "$processing_dir" ]; then
        log_error "Processing directory not found: $processing_dir"
        return 1
    fi
    
    # Create export run directory
    mkdir -p "$export_run_dir"
    
    # Count samples and exported files
    local sample_count=0
    local exported_count=0
    
    # Process each sample directory
    for sample_dir in "$processing_dir"/*; do
        # Skip if not a directory or if it's a summary file
        if [ ! -d "$sample_dir" ]; then
            continue
        fi
        
        local sample_id
        sample_id=$(basename "$sample_dir")
        
        # Skip unclassified only; keep barcode directories (they contain sample outputs)
        if [ "$sample_id" = "unclassified" ]; then
            continue
        fi
        
        sample_count=$((sample_count + 1))
        
        local export_sample_dir="$export_run_dir/$sample_id"
        
        # Don't fail the script if export_sample returns 1
        if export_sample "$sample_dir" "$export_sample_dir" || true; then
            if [ -d "$export_sample_dir" ] && [ "$(ls -A "$export_sample_dir" 2>/dev/null)" ]; then
                exported_count=$((exported_count + 1))
            fi
        fi
    done
    
    echo ""
    if [ $sample_count -eq 0 ]; then
        log_warning "No samples found in $run_id"
        return 1
    else
        log_success "Run $run_id: $exported_count/$sample_count sample(s) exported successfully"
        
        # Create TAR.GZ archive (portable across all systems)
        cd "$EXPORT_DIR" || return 1
        
        log_info "Creating TAR.GZ archive..."
        local tar_file="$EXPORT_DIR/${run_id}.tar.gz"
        
        if tar czf "${run_id}.tar.gz" "$run_id"; then
            local tar_size
            tar_size=$(du -h "$tar_file" | cut -f1)
            log_success "Archive created: ${run_id}.tar.gz (${tar_size})"
        else
            log_error "Failed to create TAR.GZ archive"
            return 1
        fi
    fi
    
    return 0
}

# Main execution
main() {
    echo "=========================================="
    echo "   Nanomito Results Export"
    echo "=========================================="
    
    # Parse arguments
    if [ $# -eq 0 ]; then
        usage "Missing required argument: RUN_PATH"
        
    elif [ $# -eq 1 ]; then
        # One argument: run path (auto-detect name from basename)
        RUN_PATH="$1"
        RUN_NAME=""
        
    elif [ $# -eq 2 ]; then
        # Two arguments: run path + custom name
        RUN_PATH="$1"
        RUN_NAME="$2"
        
    else
        usage "Too many arguments"
    fi
    
    # Validate run path
    if [ ! -d "$RUN_PATH" ]; then
        log_error "Run directory not found: $RUN_PATH"
        exit 1
    fi
    
    # Export the run
    export_run "$RUN_PATH" "$RUN_NAME"
    
    echo ""
    echo "=========================================="
    log_success "Export completed"
    echo "=========================================="
    log_info "Results exported to: $EXPORT_DIR"
}

# Show usage if --help or -h
if [ $# -gt 0 ] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

main "$@"
