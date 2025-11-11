#!/bin/bash
#
# export_results.sh - Export key result files from nanomito runs
#
# Description:
#   Copies analysis results (TSV, VCF, BAM, BAI files) from run directories
#   in /scratch/mferre/workbench to /scratch/mferre/export/<run_id>
#
# Usage:
#   ./export_results.sh [RUN_DIR]
#
# Arguments:
#   RUN_DIR (optional): Specific run directory to export
#                       If not provided, processes all runs in workbench
#
# File patterns exported per sample:
#   - *.ann.tsv                              (Annotated variants TSV)
#   - *.ann.vcf                              (Annotated variants VCF)
#   - *.chrM.sup,5mC_5hmC,6mA.sorted.bam    (Sorted BAM with modifications)
#   - *.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai (BAM index)
#
# Directory structure:
#   Source: /scratch/mferre/workbench/<run>/processing/<sample>/
#   Target: /scratch/mferre/export/<run>/<sample>/
#

set -euo pipefail

# Configuration
WORKBENCH_DIR="/scratch/mferre/workbench"
EXPORT_DIR="/scratch/mferre/export"

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
    echo "Usage: $0 [RUN_DIR]"
    echo ""
    echo "Export nanomito analysis results to organized export directory"
    echo ""
    echo "Arguments:"
    echo "  RUN_DIR    Optional: specific run directory to export"
    echo "             If omitted, all runs in $WORKBENCH_DIR are processed"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Export all runs"
    echo "  $0 /scratch/mferre/workbench/run001   # Export specific run"
    echo "  $0 run001                             # Export specific run (basename)"
    echo ""
    exit 1
}

# File patterns to export
FILE_PATTERNS=(
    "*.ann.tsv"
    "*.ann.vcf"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam"
    "*.chrM.sup,5mC_5hmC,6mA.sorted.bam.bai"
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
                ((file_count++))
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
    local run_id
    run_id=$(basename "$run_dir")
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
        
        # Skip barcode directories (from bchg step)
        if [[ "$sample_id" =~ ^(pass_)?barcode[0-9]+ ]]; then
            continue
        fi
        
        ((sample_count++))
        
        local export_sample_dir="$export_run_dir/$sample_id"
        
        if export_sample "$sample_dir" "$export_sample_dir"; then
            ((exported_count++))
        fi
    done
    
    echo ""
    if [ $sample_count -eq 0 ]; then
        log_warning "No samples found in $run_id"
        return 1
    else
        log_success "Run $run_id: $exported_count/$sample_count sample(s) exported successfully"
        
        # Create ZIP archive
        log_info "Creating ZIP archive..."
        local zip_file="$EXPORT_DIR/${run_id}.zip"
        
        # Create ZIP from the export directory
        cd "$EXPORT_DIR" || return 1
        if zip -r -q "${run_id}.zip" "$run_id"; then
            local zip_size
            zip_size=$(du -h "$zip_file" | cut -f1)
            log_success "Archive created: ${run_id}.zip (${zip_size})"
        else
            log_error "Failed to create ZIP archive"
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
    
    # Check if workbench directory exists
    if [ ! -d "$WORKBENCH_DIR" ]; then
        log_error "Workbench directory not found: $WORKBENCH_DIR"
        exit 1
    fi
    
    # Determine which runs to process
    if [ $# -eq 0 ]; then
        # No argument: process all runs
        log_info "Exporting all runs from $WORKBENCH_DIR"
        
        run_dirs=("$WORKBENCH_DIR"/*)
        
        if [ ${#run_dirs[@]} -eq 0 ]; then
            log_error "No run directories found in $WORKBENCH_DIR"
            exit 1
        fi
        
        total_runs=0
        successful_runs=0
        
        for run_dir in "${run_dirs[@]}"; do
            if [ -d "$run_dir" ]; then
                ((total_runs++))
                if export_run "$run_dir"; then
                    ((successful_runs++))
                fi
            fi
        done
        
        echo ""
        echo "=========================================="
        log_success "Export completed: $successful_runs/$total_runs run(s) processed"
        echo "=========================================="
        
    elif [ $# -eq 1 ]; then
        # One argument: process specific run
        RUN_ARG=$1
        
        # Check if it's a full path or just basename
        if [ -d "$RUN_ARG" ]; then
            RUN_DIR="$RUN_ARG"
        elif [ -d "$WORKBENCH_DIR/$RUN_ARG" ]; then
            RUN_DIR="$WORKBENCH_DIR/$RUN_ARG"
        else
            log_error "Run directory not found: $RUN_ARG"
            exit 1
        fi
        
        export_run "$RUN_DIR"
        
        echo ""
        echo "=========================================="
        log_success "Export completed"
        echo "=========================================="
        
    else
        usage
    fi
    
    log_info "Results exported to: $EXPORT_DIR"
}

# Show usage if --help or -h
if [ $# -gt 0 ] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    usage
fi

main "$@"
