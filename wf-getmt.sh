#!/bin/bash
set -e

VERSION='25.03.24.3'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

ALN_DIR='alignments'
POD5_ALL_DIR='pod5'
POD5_MT_DIR='pod5_chrM'
IDS_DIR='read_ids'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
cd $1

echo "Workflow: wf-getmt v.$VERSION by $AUTHOR"
echo "=== Get chrM data only for Nanomito ==="

RUN_PATH=`pwd`
ALN_PATH="$RUN_PATH/$ALN_DIR"
POD5_ALL_PATH="$RUN_PATH/$POD5_ALL_DIR"
POD5_MT_PATH="$RUN_PATH/$POD5_MT_DIR"
IDS_PATH="$RUN_PATH/$IDS_DIR"

echo "Run path        : $RUN_PATH"
echo "Alignments path : $ALN_PATH"
echo "Pod5 path       : $POD5_ALL_PATH"
echo "Output path     : $POD5_MT_PATH"

mkdir $IDS_PATH
echo "[OK] Read ids directory $IDS_PATH created"

#samtools --version
SAMPLES_COUNT=0
cd $ALN_PATH
for DIR in $(ls -1 -d */); do
	SAMPLES_COUNT=$((SAMPLES_COUNT+1))
	
	SAMPLE_ID=`basename $DIR`
	READ_IDS_PATH="$IDS_PATH/$SAMPLE_ID.read_ids.txt"
	READ_IDS_TMP_PATH="$READ_IDS_PATH.tmp"
	echo "--- Sample: $SAMPLE_ID"
	
	for BAM in $DIR/*.bam ; do 
		samtools view $BAM chrM | cut -f1
	done > $READ_IDS_TMP_PATH
	READ_IDS_TMP_COUNT=`wc -l --total=only $READ_IDS_TMP_PATH`
	
	sort -u $READ_IDS_TMP_PATH > $READ_IDS_PATH
	READ_IDS_COUNT=`wc -l --total=only $READ_IDS_PATH`
	echo "[OK] $READ_IDS_COUNT (from $READ_IDS_TMP_COUNT) in file $READ_IDS_PATH"
	
	if [ $READ_IDS_COUNT -eq 0 ] ; then
		echo "[WARNING]No read matching chrM: skip to next sample"
	else
		POD5_PATH="$POD5_MT_PATH/$SAMPLE_ID.chrM.pod5"
		#pod5 --version
		pod5 filter $POD5_ALL_PATH --ids $READ_IDS_PATH --missing-ok --output $POD5_PATH
		echo "[OK] Pod5 chrM only in file $POD5_PATH"
		pod5 inspect summary $POD5_PATH
	fi

done

rm -rf $IDS_PATH
echo "[OK] Read ids directory $IDS_PATH removed"

echo '|'
echo '|'
echo "| [OK] Workflow finished successfully"
echo '|'
echo '|'
echo "=== $SAMPLES_COUNT sample(s) processed ==="