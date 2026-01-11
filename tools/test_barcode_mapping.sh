#!/bin/bash
# Test script to verify barcode→alias mapping with Windows line endings

echo "Testing barcode→alias mapping fix"
echo "===================================="
echo ""

# Create a test CSV with Windows line endings (\r\n)
TEST_CSV="/tmp/test_sample_sheet.csv"
printf "experiment_id,kit,flow_cell_id,alias,barcode\r\n" > "$TEST_CSV"
printf "test001,SQK-NBD114-24,FAZ22729,SAMPLE1,barcode10\r\n" >> "$TEST_CSV"
printf "test001,SQK-NBD114-24,FAZ22729,SAMPLE2,barcode11\r\n" >> "$TEST_CSV"

echo "Test CSV file created: $TEST_CSV"
echo ""
echo "Content (with special chars visible):"
od -c "$TEST_CSV" | head -15
echo ""

# Read the CSV and create mapping, simulating what wf-bchg.sh does
declare -A BARCODE_ALIAS_OLD
declare -A BARCODE_ALIAS_NEW

echo "Reading CSV WITHOUT \r stripping (old way):"
while IFS=, read -ra COLS || [[ -n "${COLS[*]}" ]]; do
    if [ "${COLS[4]}" = "barcode" ]; then
        continue
    fi
    BARCODE_OLD="${COLS[4]}"
    ALIAS_OLD="${COLS[3]}"
    [[ -z "$BARCODE_OLD" ]] && continue
    ALIAS_OLD="${ALIAS_OLD%$'\r'}"  # Only strip from alias (old buggy way)
    BARCODE_ALIAS_OLD["$BARCODE_OLD"]="$ALIAS_OLD"
    echo "  Mapped '$BARCODE_OLD' (len=${#BARCODE_OLD}) → '$ALIAS_OLD'"
done < "$TEST_CSV"

echo ""
echo "Reading CSV WITH \r stripping from both (new fix):"
while IFS=, read -ra COLS || [[ -n "${COLS[*]}" ]]; do
    if [ "${COLS[4]}" = "barcode" ]; then
        continue
    fi
    BARCODE_NEW="${COLS[4]}"
    ALIAS_NEW="${COLS[3]}"
    BARCODE_NEW="${BARCODE_NEW%$'\r'}"  # Strip from barcode (NEW FIX)
    ALIAS_NEW="${ALIAS_NEW%$'\r'}"
    [[ -z "$BARCODE_NEW" ]] && continue
    BARCODE_ALIAS_NEW["$BARCODE_NEW"]="$ALIAS_NEW"
    echo "  Mapped '$BARCODE_NEW' (len=${#BARCODE_NEW}) → '$ALIAS_NEW'"
done < "$TEST_CSV"

echo ""
echo "Testing lookups:"
echo ""

# Test lookups for barcode10 (what will come from filename)
TEST_BARCODE="barcode10"
echo "Looking up: '$TEST_BARCODE'"

if [ -n "${BARCODE_ALIAS_OLD[$TEST_BARCODE]:-}" ]; then
    echo "  ✓ OLD way found: ${BARCODE_ALIAS_OLD[$TEST_BARCODE]}"
else
    echo "  ✗ OLD way NOT found (bug!)"
fi

if [ -n "${BARCODE_ALIAS_NEW[$TEST_BARCODE]:-}" ]; then
    echo "  ✓ NEW way found: ${BARCODE_ALIAS_NEW[$TEST_BARCODE]}"
else
    echo "  ✗ NEW way NOT found (still broken)"
fi

echo ""
echo "Array contents (old):"
for key in "${!BARCODE_ALIAS_OLD[@]}"; do
    echo "  Key: '$key' (len=${#key}) → Value: '${BARCODE_ALIAS_OLD[$key]}'"
done

echo ""
echo "Array contents (new):"
for key in "${!BARCODE_ALIAS_NEW[@]}"; do
    echo "  Key: '$key' (len=${#key}) → Value: '${BARCODE_ALIAS_NEW[$key]}'"
done

# Cleanup
rm "$TEST_CSV"
echo ""
echo "Test completed. Test file cleaned up."
