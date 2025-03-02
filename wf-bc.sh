#!/bin/bash
#SBATCH --job-name=wf-bc
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 20:00:00
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2025-01-10.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

POD5_DIR='/scratch/mferre/workbench/241202_run10/no_sample_id/20241202_1702_MN19558_FBA90343_6e5d6a93/pod5'

SAMPLE_ID=${PWD##*/} # Assign directory name to sample id
SAMPLE_ID=${SAMPLE_ID:-/} # Correct for the case where PWD=/

DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado-0.8.3-linux-x64/bin/dorado'
MODEL='sup'

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
	if [ -f "$1" ]
	then 
   		echo "[OK] File $1 created"
   	else
		echo "[ERROR] File $1 not created"
		exit 9999 # die with error code 9999
	fi
	if [ -s "$1" ]
	then 
   		echo "[OK] File $1 not empty"
   	else
		echo "[ERROR] File $1 is empty"
		exit 9999 # die with error code 9999
	fi
}

START=`date +%s`

echo "Workflow: BC v.$VERSION by $AUTHOR"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Working directory: `pwd`"
echo "Input file: $POD5_DIR"
echo "Model: $MODEL"
echo "Date: `date`"

echo
echo '***************'
echo '* Basecalling *'
echo '***************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

echo "Dorado version: "
$DORADO_BIN --version

$DORADO_BIN basecaller $MODEL $POD5_DIR \
	--recursive \
	--sample-sheet 'sample_sheet.csv' \
	> calls.bam

check_file calls.bam
$DORADO_BIN summary calls.bam > summary.tsv
check_file summary.tsv

echo
echo '******************'
echo '* Demultiplexing *'
echo '******************'

mkdir classified_reads

check_file calls.bam
check_file sample_sheet.csv
$DORADO_BIN demux \
    --output-dir classified_reads \
    --kit-name 'SQK-NBD114-24' \
    --sample-sheet sample_sheet.csv \
    calls.bam

# rm calls.bam
# echo "File removed: calls.bam"

echo
echo '***********************'
echo '* Converting to fastq *'
echo '***********************'

. /local/env/envsamtools-1.15.sh

check_dir classified_reads
cd classified_reads
for file in *.bam
do
	$DORADO_BIN summary $file > ${file//.bam/.summary.tsv}
	samtools fastq $file > ${file//.bam/.fastq}
	mkdir ../${file//.bam/}
done
echo "=> Reads generated (including header - 1 line):"
wc -l *.summary.tsv
echo "Gzip all fastq files..."
gzip *.fastq

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
