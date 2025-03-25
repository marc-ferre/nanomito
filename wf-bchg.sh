#!/bin/bash
#SBATCH --job-name=bchg
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 120
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_80
#SBATCH --mail-user=marc.ferre@univ-angers.fr
#
#
# wf-bchg.sh /Path/to/run/dir/
#
#
VERSION='25.03.24.2'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Argument = run path
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
cd $1

# Directories
RUN_DIR=`pwd`
POD5_DIR="$RUN_DIR/pod5_chrM"
FASTQ_DIR="$RUN_DIR/fastq_pass"
PROCESS_DIR="$RUN_DIR/processing"

# Files
SAMPLESHEET_FILE=`readlink -f "$(find . -type f -name 'sample_sheet_*.csv')"`

# Basecalling model
MODEL='sup'

# Binary and Conda env
DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.9.1-linux-x64/bin/dorado'

# Prefixes
RUN_ID=`basename $RUN_DIR`

# Files
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

check_dir () { 
	if [ -d "$1" ]
	then 
   		echo "[OK] Directory $1 exists"
   	else
		echo "[ERROR] Directory $1 doesn't exist"
		exit 9999 # die with error code 9999
	fi
}
check_file () { 
	if [ -f "$1" ] && [ -s "$1" ]
	then 
   		echo "[OK] File $1 exists and is not empty"
   	else
		echo "[ERROR] File $1 is empty or doesn't exist"
		exit 9999 # die with error code 9999
	fi
}

START=`date +%s`

echo "Workflow: wf-bchg v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory  : $RUN_DIR"
echo "Pod5 directory : $POD5_DIR"
echo "FastQ directory: $FASTQ_DIR"
echo "Model: $MODEL"
echo "Date : `date`"

echo
echo '***************'
echo '* Basecalling *'
echo '***************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

check_dir $POD5_DIR

echo "Dorado version:"
$DORADO_BIN --version

$DORADO_BIN basecaller $MODEL $POD5_DIR --sample-sheet $SAMPLESHEET_FILE --min-qscore 9 --emit-fastq --output-dir $FASTQ_DIR
check_dir $FASTQ_DIR

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

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > $WORKFLOW_SUMMARY_FILE
	echo "[OK] File $WORKFLOW_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID	$SAMPLE_ID	bchg	$HOURS:$MINUTES:$SECONDS" >> $WORKFLOW_SUMMARY_FILE
echo "[OK] Line added to $WORKFLOW_SUMMARY_FILE"
