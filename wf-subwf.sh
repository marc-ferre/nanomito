#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh /Path/to/run/dir/
#
set -e

WF_DEMULTMT='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-demultmt.sh'
WF_MODMITO='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-modmito.sh'

FASTQ_DIR='fastq_pass'
POD5_DIR='pod5'
PROCESS_DIR='processing'

MAIL_TYPE_CUSTOM='END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_ALL='ALL'
MAIL_TYPE_NONE='NONE'

MAIL_USER='marc.ferre@univ-angers.fr'

if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
cd $1

echo "=== Submit workflows to Slurm ==="

RUN_PATH=`pwd`
FASTQ_PATH="$RUN_PATH/$FASTQ_DIR"
POD5_PATH="$RUN_PATH/$POD5_DIR"
PROCESS_PATH="$RUN_PATH/$PROCESS_DIR"

echo "Run path   : $RUN_PATH"
echo "FastQ path : $FASTQ_PATH"
echo "Pod5 path  : $POD5_PATH"
echo "Output path: $PROCESS_PATH"

SAMPLES_COUNT=0
JOBS_COUNT=0
cd $FASTQ_PATH
for DIR in $(ls -1); do
	SAMPLE_ID=`basename $DIR`
	echo "--- Sample: $SAMPLE_ID"
	
	SAMPLES_COUNT=$((SAMPLES_COUNT+1))
	
	OUT_PATH="$PROCESS_PATH/$SAMPLE_ID"
	SLURM_PRE="slurm-$SAMPLE_ID"
	SLURM_EXT='txt'
	
	WF_ID='demultmt'
	SLURM_FILE="$OUT_PATH/$SLURM_PRE.$WF_ID.$SLURM_EXT"
#	JOBID=$(sbatch --parsable --chdir="$RUN_PATH" --job-name="${WF_ID:0:1}${SAMPLE_ID: -5}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_CUSTOM" --mail-user="$MAIL_USER" $WF_DEMULTMT $SAMPLE_ID)
	echo "> Submitted batch job $JOBID"
	echo "  Output in $SLURM_FILE"
	JOBS_COUNT=$((JOBS_COUNT+1))
	
# 	WF_ID='modmito'
# 	SLURM_FILE="$OUT_PATH/$SLURM_PRE.$WF_ID.$SLURM_EXT"
# 	JOBID=(sbatch --dependency=afterok:${JOBID} --chdir="$RUN_PATH" --job-name="${WF_ID:0:1}${SAMPLE_ID: -5}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_CUSTOM" --mail-user="$MAIL_USER" $WF_MODMITO $SAMPLE_ID)
# 	echo "> Submitted batch job $JOBID"
# 	echo "  Output in $SLURM_FILE"
#	JOBS_COUNT=$((JOBS_COUNT+1))

done

echo "=== $SAMPLES_COUNT sample(s)/$JOBS_COUNT batch job(s) submitted ==="

# TODO: scancel ...
