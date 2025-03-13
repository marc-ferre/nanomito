#!/bin/bash
#SBATCH --job-name=archiving
#SBATCH --constraint avx2
#SBATCH --time 30
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr

VERSION='25.03.13.2'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
RUN_DIR=$1
RUN_ID=$(basename $RUN_DIR_PATH)

if [ $# -eq 1 ]
	then
		echo "[ERROR] Second argument missing"
		exit 9999 # die with error code 9999
fi
ARCHIVING_DIR=$2

REMOVED_DIR="$RUN_DIR/pod5 $RUN_DIR/fastq_pass"

START=`date +%s`

echo "Workflow: wf-archiving v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Archiving directory: $ARCHIVING_DIR"
echo "Date: `date`"

echo
echo '*********'
echo '* Clean *'
echo '*********'

echo "Remove directories: $REMOVED_DIR"

rm -rf $REMOVED_DIR

echo
echo '********'
echo '* Copy *'
echo '********'

echo "From: $RUN_DIR "
echo "To  : $ARCHIVING_DIR "

rsync -av --stats --progress --delete $RUN_DIR $ARCHIVING_DIR

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=`date +%s`
RUNTIME=$(echo "$END - $START")
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
echo "Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"