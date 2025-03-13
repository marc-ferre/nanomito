#!/bin/bash
#SBATCH --job-name=archiving
#SBATCH --constraint avx2
#SBATCH --time 30
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr

VERSION='25.03.13.4'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
RUN_DIR=$1
RUN_ID=$(basename $RUN_DIR)

if [ $# -eq 1 ]
	then
		echo "[ERROR] Second argument missing"
		exit 9999 # die with error code 9999
fi
ARCHIVING_DIR=$2

# Directories to remove
FASTQ_DIR="$RUN_DIR/fastq_pass"
POD5_DIR="$RUN_DIR/pod5"

START=`date +%s`

echo "Workflow: wf-archiving v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Archiving directory: $ARCHIVING_DIR"
echo "Date: `date`"

echo
echo '*************'
echo '* Clean run *'
echo '*************'

clean_dir () {
	DIR_TO_CLEAN=$1

	if [ -d "$DIR_TO_CLEAN" ]; then
			rm -Rf $DIR_TO_CLEAN
			if [ $? -eq 0 ]; then
    			echo "[OK] Directory cleaned successfully: $DIR_TO_CLEAN"
			else
    			echo "[ERROR] Can't clean directory: $DIR_TO_CLEAN"
    			exit 9999 # die with error code 9999
			fi
	else
		echo "[WARNING] Directory doesn't exist: $DIR_TO_CLEAN"
	fi
}

clean_dir $FASTQ_DIR
clean_dir $POD5_DIR

echo
echo '************'
echo '* Copy run *'
echo '************'

echo "From: $RUN_DIR "
echo "To  : $ARCHIVING_DIR "

rsync -av --stats --progress --delete $RUN_DIR $ARCHIVING_DIR
if [ $? -eq 0 ]; then
    echo "[OK] Run copied successfully"
else
    echo "[ERROR] While copying"
    exit 9999 # die with error code 9999
fi

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