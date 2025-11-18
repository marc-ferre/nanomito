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
LOGFILE="$OUTFILE.anonymize.log"

echo "Checking results (no hash)..."
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

echo "[OK] Anonymization test passed (no hash)"

echo "Running anonymization test with --hash..."
"$TOOL" "SAMPLE1" ANON "$TESTVCF" --hash

OUTFILE_HASH="$TESTDIR/$(basename "$TESTVCF" | sed 's/SAMPLE1/ANON/g')"
LOGFILE_HASH="$OUTFILE_HASH.anonymize.log"

echo "Checking results (with hash)..."
if [ ! -f "$OUTFILE_HASH" ]; then
    echo "[FAIL] Output file not found: $OUTFILE_HASH" >&2
    exit 5
fi

if grep -q "SAMPLE1" -- "$OUTFILE_HASH"; then
    echo "[FAIL] Found original identifier SAMPLE1 in hashed output file" >&2
    exit 6
fi

if [ ! -f "$LOGFILE_HASH" ]; then
    echo "[FAIL] Log file not found: $LOGFILE_HASH" >&2
    exit 7
fi

# Check header contains anonymizeHashes
if ! grep -q "##anonymizeHashes" -- "$OUTFILE_HASH"; then
    echo "[FAIL] anonymizeHashes header not found in output" >&2
    exit 8
fi

# Check log contains original identifier mapping
if ! grep -q "SAMPLE1" -- "$LOGFILE_HASH"; then
    echo "[FAIL] Original identifier mapping not found in log" >&2
    exit 9
fi

echo "[OK] Anonymization test passed (with hash)"
echo "Output: $OUTFILE_HASH"
echo "Log: $LOGFILE_HASH"

exit 0
