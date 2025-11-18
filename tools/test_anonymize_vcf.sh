#!/usr/bin/env bash
set -euo pipefail

# Simple test for tools/anonymize_vcf.sh
ROOTDIR=$(cd "$(dirname "$0")" && pwd)
TESTDIR="$ROOTDIR/test_data"
TESTVCF="$TESTDIR/sample_SAMPLE1.vcf"
TOOL="$ROOTDIR/anonymize_vcf.sh"

if [ ! -x "$TOOL" ]; then
    echo "Making tool executable"
    chmod +x "$TOOL"
fi

echo "Running anonymization test..."
"$TOOL" "SAMPLE1" ANON "$TESTVCF"

OUTFILE="$TESTDIR/$(basename "$TESTVCF" | sed 's/SAMPLE1/ANON/g')"
LOGFILE="$TESTDIR/$(basename "$TESTVCF").anonymize.log"

echo "Checking results..."
if [ ! -f "$OUTFILE" ]; then
    echo "[FAIL] Output file not found: $OUTFILE" >&2
    exit 2
fi

if grep -q "SAMPLE1" -- "$OUTFILE"; then
    echo "[FAIL] Found original identifier SAMPLE1 in output file" >&2
    exit 3
fi

if [ ! -f "$LOGFILE" ]; then
    echo "[FAIL] Log file not found: $LOGFILE" >&2
    exit 4
fi

echo "[OK] Anonymization test passed"
echo "Output: $OUTFILE"
echo "Log: $LOGFILE"

exit 0
