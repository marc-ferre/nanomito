#!/bin/bash
#
# Submit Nanomito workflows to Slurm
#
# submit_nanomito.sh /Path/to/run/dir/
#
set -e

WF_BCHG='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-bchg.sh'
WF_SUBWF='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-subwf.sh'

FASTQ_DIR='fastq_pass'
POD5_DIR='pod5_chrM'
PROCESS_DIR='processing'

MAIL_TYPE_ALL='ALL'
MAIL_TYPE_END='END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_ISSUE='FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
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
RUN_ID=`basename $RUN_PATH`
FASTQ_PATH="$RUN_PATH/$FASTQ_DIR"
POD5_PATH="$RUN_PATH/$POD5_DIR"
PROCESS_PATH="$RUN_PATH/$PROCESS_DIR"

echo "Run path   : $RUN_PATH"
echo "FastQ path : $FASTQ_PATH"
echo "Pod5 path  : $POD5_PATH"
echo "Output path: $PROCESS_PATH"

JOBID_LIST=''
# cd $FASTQ_PATH
# for DIR in $(ls -1); do
# 	SAMPLE_ID=`basename $DIR`
# 	echo "--- Sample: $SAMPLE_ID"
	
	
	OUT_PATH=$PROCESS_PATH
	SLURM_PRE="slurm-$RUN_ID"
	SLURM_EXT='txt'
	
	WF_ID='bchg'
	SLURM_FILE="$OUT_PATH/$SLURM_PRE.$WF_ID.$SLURM_EXT"
	JOBID=$(sbatch --parsable --chdir="$RUN_PATH" --job-name="${WF_ID:0:1}${RUN_ID: -5}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" $WF_DEMULTMT $RUN_PATH)
	echo "> Submitted batch job $JOBID"
	echo "  Output in $SLURM_FILE"
	JOBID_LIST="$JOBID $JOBID_LIST"
	
	WF_ID='subwf'
	SLURM_FILE="$OUT_PATH/$SLURM_PRE.$WF_ID.$SLURM_EXT"
	JOBID=(sbatch --dependency=afterok:${JOBID} --chdir="$RUN_PATH" --job-name="${WF_ID:0:1}${RUN_ID: -5}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" $WF_MODMITO $RUN_PATH)
	echo "> Submitted batch job $JOBID"
	echo "  Output in $SLURM_FILE"
	JOBID_LIST="$JOBID $JOBID_LIST"

# done

echo "=== $SAMPLES_COUNT sample(s)/$JOBS_COUNT batch job(s) submitted ==="
echo "|"
echo "| Use following command to cancel all jobs:"
echo "|"
echo "| scancel $JOBID_LIST"
echo "|"
echo "|"
echo "|"
