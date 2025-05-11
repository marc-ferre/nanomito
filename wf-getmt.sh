#!/bin/bash
#
# getmt.sh /Path/to/run/dir
#
# Script to filter raw data (Pod5) from nanopore sequencing reads aligned (BAM) to chrM
#
# Requires conda environment
#    name: /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_getmt
#    channels:
#      - anaconda
#      - conda-forge
#      - bioconda
#      - nodefaults
#    dependencies:
#      - pod5
#      - pysam
#
# Requires Python script: get_chrMpid.py
#
set -e

VERSION='25.05.09.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Run id = Argument
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 128 # die with error code 9999
fi
cd "$1"
RUN_ID=${PWD##*/} # Assign directory name to run id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Directories
RUN_DIR_PATH=$(pwd)
BAM_DIR="$RUN_DIR_PATH/alignment"
POD5_ALL_DIR="$RUN_DIR_PATH/pod5"
POD5_MT_DIR="$RUN_DIR_PATH/pod5_chrM"

# Scripts
CHRMPIDS_SCRIPT='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/get_chrMpid.py'

# Files
CHRMPIDS_FILE="$POD5_MT_DIR/$RUN_ID.chrM_pids.txt"
POD5_MT_FILE="$POD5_MT_DIR/$RUN_ID.chrM.pod5"

echo "Workflow  : wf-getmt v.$VERSION by $AUTHOR"
echo "——————————— Get IDs of Pod5 reads matching chrM for Nanomito ———————————"
echo "Run       : $RUN_ID"
echo "Run dir   : $RUN_DIR_PATH"
echo "BAM dir   : $BAM_DIR"
echo "POD5 dir  : $POD5_ALL_DIR"
echo "Output dir: $POD5_MT_DIR"

mkdir "$POD5_MT_DIR"
echo "[OK] chrM POD5 directory created: $POD5_MT_DIR"

# Get unique parent IDs (pid) of reads aligned to chrM 
python3 $CHRMPIDS_SCRIPT -b "$BAM_DIR" -o "$CHRMPIDS_FILE"

READ_IDS_COUNT=$(wc -l --total=only "$CHRMPIDS_FILE")
echo "[OK] $READ_IDS_COUNT IDs of Pod5 reads matching chrM in file $CHRMPIDS_FILE"

# Get Pod5 raw data of reads aligned to chrM
if [ "$READ_IDS_COUNT" -eq 0 ] ; then
	echo '[WARNING] No read matching chrM: ending without Pod5 file of reads matching chrM'
else
	pod5 --version
	pod5 filter "$POD5_ALL_DIR" --ids "$CHRMPIDS_FILE" --output "$POD5_MT_FILE"
	echo "[OK] Pod5 reads matching chrM in file: $POD5_PATH"
	pod5 inspect summary "$POD5_MT_FILE"
fi

# rm $CHRMPIDS_FILE
# echo "[OK] IDs fiel of Pod5 reads matching chrM removed: $CHRMPIDS_FILE"

echo '|'
echo '|'
echo "| Workflow finished successfully. Pod5 data generated:"
echo "| $(du -hs "$POD5_MT_DIR")"
echo '|'
echo '|'
