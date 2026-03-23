#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
# Test script to verify haplocheck issue with Nanopore VCF files
# The problem: HPL (FORMAT field) needs to be converted to AF (INFO field)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Haplocheck VCF Format Test"
echo "=========================================="
echo ""

# Check if input file provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No VCF file provided${NC}"
    echo "Usage: $0 <vcf_file>"
    exit 1
fi

VCF_INPUT="$1"

if [ ! -f "$VCF_INPUT" ]; then
    echo -e "${RED}Error: File not found: $VCF_INPUT${NC}"
    exit 1
fi

echo -e "${YELLOW}Testing VCF:${NC} $VCF_INPUT"
echo ""

# Check if HPL field exists
echo "1. Checking for HPL field in VCF header..."
if grep -q "##FORMAT=<ID=HPL" "$VCF_INPUT"; then
    echo -e "${GREEN}✓ HPL field found (Nanopore format)${NC}"
    HAS_HPL=true
else
    echo -e "${YELLOW}✗ HPL field not found${NC}"
    HAS_HPL=false
fi

# Check if AF field exists in INFO
echo ""
echo "2. Checking for AF field in INFO..."
if grep -q "##INFO=<ID=AF" "$VCF_INPUT"; then
    echo -e "${GREEN}✓ AF field found in INFO${NC}"
    HAS_AF_INFO=true
else
    echo -e "${YELLOW}✗ AF field not found in INFO${NC}"
    HAS_AF_INFO=false
fi

# Show sample data line
echo ""
echo "3. Sample data lines:"
echo "---"
grep -v "^#" "$VCF_INPUT" | head -3 | cut -f1-10
echo "---"

# Extract HPL values from sample
echo ""
echo "4. HPL values in sample (first 10 variants):"
bcftools query -f '%CHROM:%POS\t%REF>%ALT\t[HPL=%HPL]\n' "$VCF_INPUT" 2>/dev/null | head -10 || echo "Error extracting HPL"

echo ""
echo "5. AF values in INFO (first 10 variants):"
bcftools query -f '%CHROM:%POS\t%REF>%ALT\tAF=%AF\n' "$VCF_INPUT" 2>/dev/null | head -10 || echo "Error extracting AF"

# Recommendation
echo ""
echo "=========================================="
echo "DIAGNOSTIC:"
echo "=========================================="

if [ "$HAS_HPL" = true ] && [ "$HAS_AF_INFO" = false ]; then
    echo -e "${RED}⚠ PROBLEM IDENTIFIED:${NC}"
    echo "  - HPL field present (Nanopore heteroplasmy rate)"
    echo "  - AF field absent in INFO"
    echo "  - Haplocheck likely won't work correctly"
    echo ""
    echo -e "${YELLOW}SOLUTION:${NC}"
    echo "  Convert HPL (FORMAT) to AF (INFO) before running haplocheck"
    echo "  Use: bcftools +fill-tags with appropriate options"
elif [ "$HAS_AF_INFO" = true ]; then
    echo -e "${GREEN}✓ AF field present in INFO${NC}"
    echo "  This VCF should work with haplocheck"
else
    echo -e "${YELLOW}⚠ Neither HPL nor AF found${NC}"
    echo "  Cannot determine heteroplasmy information"
fi

echo ""
