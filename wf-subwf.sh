#!/bin/bash
#SBATCH --job-name=subwf
#SBATCH --time 5
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr
#
#
# wf-subwf.sh /Path/to/run/dir/
#
#
set -e

VERSION='25.03.27.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Directories
RUN_DIR=`pwd`
FASTQ_DIR="$RUN_DIR/fastq_pass"
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=`basename $RUN_DIR`

# Files
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

# Workflows shell scripts
WF_DEMULTMT='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-demultmt.sh'
WF_MODMITO='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/workflows/wf-modmito.sh'

# Mail options
MAIL_USER='marc.ferre@univ-angers.fr'
MAIL_TYPE_ALL='ALL'
MAIL_TYPE_END='END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_ISSUE='FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90'
MAIL_TYPE_NONE='NONE'

START=`date +%s`

echo "=== Submit workflows to Slurm ==="
echo "Workflow: wf-subwf v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run dir   : $RUN_DIR"
echo "FastQ dir : $FASTQ_DIR"
echo "Output dir: $PROCESS_DIR"
echo "Date: `date`"

SAMPLES_COUNT=0
JOBS_COUNT=0
JOBID_LIST=''
cd $FASTQ_DIR
for DIR in $(ls -1 -d */); do
	SAMPLE_ID=`basename $DIR`
	echo "--- Sample: $SAMPLE_ID"
	
	SAMPLES_COUNT=$((SAMPLES_COUNT+1))
	
	OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
	SLURM_PRE="slurm-$SAMPLE_ID"
	SLURM_EXT='txt'
	
	WF_ID='demultmt'
	SLURM_FILE="$OUT_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"
	JOBID=$(sbatch --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_ISSUE" --mail-user="$MAIL_USER" $WF_DEMULTMT $SAMPLE_ID)
	echo "> Submitted batch job $JOBID"
	echo "  Output in $SLURM_FILE"
	JOBS_COUNT=$((JOBS_COUNT+1))
	JOBID_LIST="$JOBID $JOBID_LIST"
	
	WF_ID='modmito'
	SLURM_FILE="$OUT_DIR/$SLURM_PRE.$WF_ID.$SLURM_EXT"
 	JOBID=$(sbatch  --dependency=afterok:${JOBID} --parsable --chdir="$RUN_DIR" --job-name="${WF_ID:0:1}${SAMPLE_ID: -7}" --output="$SLURM_FILE" --mail-type="$MAIL_TYPE_END" --mail-user="$MAIL_USER" $WF_MODMITO $SAMPLE_ID)
	echo "> Submitted batch job $JOBID"
	echo "  Output in $SLURM_FILE"
	JOBS_COUNT=$((JOBS_COUNT+1))
	JOBID_LIST="$JOBID $JOBID_LIST"
done

echo "=== $SAMPLES_COUNT sample(s)/$JOBS_COUNT batch job(s) submitted ==="

echo "|"
echo "| Use following command to cancel all jobs:"
echo "|"
echo "| scancel $JOBID_LIST"
echo "|"
echo "|"
echo "|"

END=`date +%s`
RUNTIME=$(echo "$END - $START")
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))

echo "| Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"
echo "|"

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > $WORKFLOW_SUMMARY_FILE
	echo "[OK] File $WORKFLOW_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID		subwf	$HOURS:$MINUTES:$SECONDS" >> $WORKFLOW_SUMMARY_FILE
echo "[OK] Line added to $WORKFLOW_SUMMARY_FILE"