#!/bin/bash
#
# Test script to verify the haplocheck fix
# 1. Apply fix_vcf_for_haplocheck.sh to an annotated VCF
# 2. Run haplocheck on both original and fixed VCF
# 3. Compare haplogroup results
#

set -euo pipefail

# Usage
if [ $# -lt 1 ]; then
    echo "Usage: $0 <input_vcf> [haplocheck_jar]"
    echo ""
    echo "Example: $0 /path/to/240503_DEL-1.ann.vcf"
    exit 1
fi

INPUT_VCF="$1"
HAPLOCHECK_JAR="${2:-/local/env/envhaplocheck.jar}"

if [ ! -f "$INPUT_VCF" ]; then
    echo "Error: Input VCF not found: $INPUT_VCF"
    exit 1
fi

if [ ! -f "$HAPLOCHECK_JAR" ]; then
    echo "Error: Haplocheck JAR not found: $HAPLOCHECK_JAR"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX_SCRIPT="$SCRIPT_DIR/fix_vcf_for_haplocheck.sh"

if [ ! -f "$FIX_SCRIPT" ]; then
    echo "Error: fix_vcf_for_haplocheck.sh not found: $FIX_SCRIPT"
    exit 1
fi

# Output directory
OUTPUT_DIR="$(dirname "$INPUT_VCF")/haplocheck_test"
mkdir -p "$OUTPUT_DIR"

BASENAME="$(basename "$INPUT_VCF" .vcf)"
FIXED_VCF="$OUTPUT_DIR/${BASENAME}.fixed.vcf"

echo "=================================================="
echo "Haplocheck Fix Test"
echo "=================================================="
echo "Input VCF:    $INPUT_VCF"
echo "Fixed VCF:    $FIXED_VCF"
echo "Output dir:   $OUTPUT_DIR"
echo ""

# Step 1: Fix the VCF
echo "[1/3] Fixing VCF for haplocheck..."
bash "$FIX_SCRIPT" "$INPUT_VCF" "$FIXED_VCF"
echo ""

# Step 2: Run haplocheck on original VCF
echo "[2/3] Running haplocheck on ORIGINAL VCF..."
ORIG_OUT="$OUTPUT_DIR/${BASENAME}.original.haplocheck.txt"
java -jar "$HAPLOCHECK_JAR" --in "$INPUT_VCF" --out "$ORIG_OUT" 2>&1 | head -20
echo "Original haplocheck output: $ORIG_OUT"
echo ""

# Step 3: Run haplocheck on fixed VCF
echo "[3/3] Running haplocheck on FIXED VCF..."
FIXED_OUT="$OUTPUT_DIR/${BASENAME}.fixed.haplocheck.txt"
java -jar "$HAPLOCHECK_JAR" --in "$FIXED_VCF" --out "$FIXED_OUT" 2>&1 | head -20
echo "Fixed haplocheck output: $FIXED_OUT"
echo ""

# Compare results
echo "=================================================="
echo "COMPARISON"
echo "=================================================="
echo ""
echo "Original haplogroup:"
if [ -f "$ORIG_OUT" ]; then
    grep -v "^#" "$ORIG_OUT" | head -5 || echo "No results"
else
    echo "Output file not found"
fi

echo ""
echo "Fixed haplogroup:"
if [ -f "$FIXED_OUT" ]; then
    grep -v "^#" "$FIXED_OUT" | head -5 || echo "No results"
else
    echo "Output file not found"
fi

echo ""
echo "=================================================="
echo "Test completed!"
echo "=================================================="
