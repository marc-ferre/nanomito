#!/usr/bin/env bash
set -euo pipefail

# Version from git tags (fallback to 'unknown' if not in git repo)
VERSION="$(git -C "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" describe --tags 2>/dev/null || echo 'unknown')"

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
LOGFILE="$OUTFILE.log"

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
LOGFILE_HASH="$OUTFILE_HASH.log"

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

# Test --dry-run and --out-dir
TMP_OUT="$TESTDIR/tmp_out"
rm -rf "$TMP_OUT"
mkdir -p "$TMP_OUT"

echo "Testing --dry-run (no files should be created)..."
"$TOOL" "SAMPLE1" ANON "$TESTVCF" --out-dir "$TMP_OUT" --dry-run
if [ -n "$(find "$TMP_OUT" -mindepth 1 -print -quit 2>/dev/null || true)" ]; then
    echo "[FAIL] --dry-run created files in $TMP_OUT" >&2
    exit 10
fi
echo "[OK] --dry-run produced no files"

echo "Testing --out-dir (files should be written)..."
"$TOOL" "SAMPLE1" ANON "$TESTVCF" --out-dir "$TMP_OUT" --hash
OUT_IN_OUTDIR="$TMP_OUT/$(basename "$TESTVCF" | sed 's/SAMPLE1/ANON/g')"
LOG_IN_OUTDIR="$OUT_IN_OUTDIR.log"
if [ ! -f "$OUT_IN_OUTDIR" ]; then
    echo "[FAIL] Expected output in out-dir not found: $OUT_IN_OUTDIR" >&2
    exit 11
fi
if [ ! -f "$LOG_IN_OUTDIR" ]; then
    echo "[FAIL] Expected log in out-dir not found: $LOG_IN_OUTDIR" >&2
    exit 11
fi
if ! grep -q "##anonymizeHashes" -- "$OUT_IN_OUTDIR"; then
    echo "[FAIL] anonymizeHashes header not found in out-dir output" >&2
    exit 12
fi
echo "[OK] --out-dir produced expected files"

# Test recursive behavior on directory input
TMP_OUT2="$TESTDIR/tmp_out2"
rm -rf "$TMP_OUT2"
mkdir -p "$TMP_OUT2"
echo "Testing recursive on directory input..."
"$TOOL" "SAMPLE1" ANON "$TESTDIR" --out-dir "$TMP_OUT2" --hash --recursive
# Expect sample_ANON.vcf under TMP_OUT2
if [ ! -f "$TMP_OUT2/$(basename "$TESTVCF" | sed 's/SAMPLE1/ANON/g')" ]; then
    echo "[FAIL] Recursive output not found in $TMP_OUT2" >&2
    exit 13
fi
echo "[OK] Recursive directory anonymization succeeded"

echo "All tests passed"

exit 0
