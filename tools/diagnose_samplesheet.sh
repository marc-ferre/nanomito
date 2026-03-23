#!/bin/bash
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
#
# Diagnostic script to identify issues with sample sheet processing
# Helps troubleshoot barcode/alias assignment problems
#
# Usage: ./diagnose_samplesheet.sh /path/to/run/dir/
#

if [ $# -eq 0 ]; then
    echo "Usage: $0 /path/to/run/dir/"
    exit 1
fi

RUN_DIR="$1"

if [ ! -d "$RUN_DIR" ]; then
    echo "[ERROR] Directory does not exist: $RUN_DIR"
    exit 1
fi

echo "========================================"
echo "   SAMPLESHEET DIAGNOSTICS"
echo "========================================"
echo ""
echo "Run directory: $RUN_DIR"
echo ""

# Find all CSV files that might be sample sheets
echo "--- Step 1: Searching for sample sheet files ---"
echo ""

echo "Files matching 'sample*sheet*.csv' (case-insensitive):"
find "$RUN_DIR" -maxdepth 3 -type f -iname 'sample*sheet*.csv' | while read -r f; do
    echo "  - $f"
    echo "    Size: $(wc -c < "$f") bytes"
    echo "    Lines: $(wc -l < "$f")"
done

echo ""
echo "All CSV files in run directory (depth <= 3):"
find "$RUN_DIR" -maxdepth 3 -type f -name '*.csv' | while read -r f; do
    echo "  - $f"
done

# Analyze first matching sample sheet
SAMPLESHEET=$(find "$RUN_DIR" -maxdepth 3 -type f -iname 'sample*sheet*.csv' | head -1)

if [ -z "$SAMPLESHEET" ]; then
    echo ""
    echo "[WARNING] No sample sheet found!"
    exit 0
fi

echo ""
echo "--- Step 2: Analyzing sample sheet ---"
echo "File: $SAMPLESHEET"
echo ""

# Display header
echo "Header line:"
head -n 1 "$SAMPLESHEET" | cat -A  # Show special characters too
echo ""

# Display all columns
echo "Columns in sample sheet:"
head -n 1 "$SAMPLESHEET" | tr -d '\r' | tr ',' '\n' | nl
echo ""

# Check for specific columns
echo "Column analysis:"
HEADER=$(head -n 1 "$SAMPLESHEET" | tr -d '\r')

if echo "$HEADER" | grep -q 'barcode'; then
    BARCODE_COL=$(echo "$HEADER" | tr ',' '\n' | grep -n 'barcode' | cut -d: -f1)
    echo "  [OK] 'barcode' column found at position $BARCODE_COL"
else
    echo "  [ERROR] 'barcode' column NOT found"
fi

if echo "$HEADER" | grep -q 'alias'; then
    ALIAS_COL=$(echo "$HEADER" | tr ',' '\n' | grep -n 'alias' | cut -d: -f1)
    echo "  [OK] 'alias' column found at position $ALIAS_COL"
else
    echo "  [WARNING] 'alias' column NOT found"
fi

if echo "$HEADER" | grep -q 'kit'; then
    echo "  [OK] 'kit' column found"
else
    echo "  [ERROR] 'kit' column NOT found (required for Dorado)"
fi

if echo "$HEADER" | grep -q 'experiment_id'; then
    echo "  [OK] 'experiment_id' column found"
else
    echo "  [ERROR] 'experiment_id' column NOT found (required for Dorado)"
fi

if echo "$HEADER" | grep -q 'flow_cell_id\|position_id'; then
    echo "  [OK] 'flow_cell_id' or 'position_id' column found"
else
    echo "  [ERROR] Neither 'flow_cell_id' nor 'position_id' column found (one is required)"
fi

echo ""
echo "--- Step 3: Data preview ---"
echo ""

# Show first few rows with line numbers
echo "First 5 rows of sample sheet:"
head -n 5 "$SAMPLESHEET" | nl

echo ""
echo "--- Step 4: Checking for barcode/alias values ---"
echo ""

if [ "$BARCODE_COL" -gt 0 ] && [ "$ALIAS_COL" -gt 0 ]; then
    echo "Barcode → Alias mappings found:"
    tail -n +2 "$SAMPLESHEET" | tr -d '\r' | awk -F, -v bc="$BARCODE_COL" -v ac="$ALIAS_COL" 'NF>=ac && $bc!="" {printf "  %s → %s\n", $bc, $ac}'
else
    echo "[INFO] Cannot extract barcode/alias mappings (one or both columns missing)"
fi

echo ""
echo "========================================"
echo "           END OF DIAGNOSTICS"
echo "========================================"
