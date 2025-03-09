#!/bin/bash
#SBATCH --job-name=wf-demultmt
#SBATCH --cpus-per-task=12
#SBATCH --mem=150G
#SBATCH --time 30
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='2025-03-08.5'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Run Id = Working directory
RUN_ID=${PWD##*/} # Assign directory name to sample id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Sample Id = Argument
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
SAMPLE_ID=$1

# Read selection strategy (start, both, either ,xor)
SELECT='both' 

WORK_DIR=`pwd`
FASTQ_DIR="$WORK_DIR/fastq_pass/$SAMPLE_ID"
POD5_DIR="$WORK_DIR/pod5"
OUT_DIR="$WORK_DIR/processing/$SAMPLE_ID"
SELECT_DIR="$OUT_DIR/select-$SELECT"

MINIMAP2_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/minimap2-2.28_x64-linux/minimap2'
ONT_DEMULT_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/ont_demult/target/release/ont_demult'
MODKIT_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_modkit'

REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'
REF_MT_2KB='/scratch/mferre/reference/chrM-mt_2kb.fa'
REF_MT_3KB='/scratch/mferre/reference/chrM-mt_3kb.fa'
REF_MT_10KB='/scratch/mferre/reference/chrM-mt_10kb.fa'

CUT_FILE='/scratch/mferre/reference/cut.txt'
DEMULT_PREFIX="$SAMPLE_ID.ont_demult"
IDS_FILE="$SELECT_DIR/read_ids.txt"

DEMULT_SUMMARY_FILE="$OUT_DIR/demult_summary.$RUN_ID.tsv"
DEMULT_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.txt.gz"
CHRM_ONLY_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.match_chrM_only.txt"
MATCH_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.matched.txt"

BAM_FILE="$SELECT_DIR/$SAMPLE_ID.bam"
SORTED_BAM_FILE="$SELECT_DIR/$SAMPLE_ID.sorted.bam"

DEMULT_POD5_FILE="$OUT_DIR/$SAMPLE_ID.demultmt.pod5"

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
   		echo "[OK] File $1 exists"
   	else
		echo "[ERROR] File $1 doesn't exist"
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

echo "Workflow: $SLURM_JOB_NAME v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Working directory: $WORK_DIR"
echo "Pod5 directory: $POD5_DIR"
echo "FastQ directory: $FASTQ_DIR"
echo "Output directory: $OUT_DIR"
echo "Date: `date`"

echo
echo '*****************'
echo '* Preprocessing *'
echo '*****************'
check_dir $POD5_DIR
check_dir $FASTQ_DIR
mkdir -p $OUT_DIR
FASTQ_FILE="$OUT_DIR/$SAMPLE_ID.fastq.gz"
echo "FastQ file: $FASTQ_FILE"
MAPPING_FILE="$OUT_DIR/$SAMPLE_ID.paf"
echo "Mapping file: $MAPPING_FILE"

cat $FASTQ_DIR/*.fastq.gz > $FASTQ_FILE
check_file $FASTQ_FILE
COUNT_TOTAL=$(expr $(zcat $FASTQ_FILE|wc -l)/4|bc)

echo
echo '******************************'
echo '* Mapping Standard Reference *'
echo '******************************'

echo "Minimap2 version: `$MINIMAP2_BIN --version`"

$MINIMAP2_BIN -x map-ont -t 10 $REF_WHOLE $FASTQ_FILE > $MAPPING_FILE
check_file $MAPPING_FILE

echo
echo '******************'
echo '* Demultiplexing *'
echo '******************'
echo "`$ONT_DEMULT_BIN --version`"

echo
echo '|'
echo "| Selection strategy: $SELECT"
echo '|'

mkdir $SELECT_DIR
check_dir $SELECT_DIR
cd $SELECT_DIR

check_file $MAPPING_FILE

$ONT_DEMULT_BIN --select $SELECT \
	--loglevel info \
	--mapq-threshold 10 \
	--max-distance 100 \
	--max-unmatched 200 \
	--margin 10 \
	--cut-file $CUT_FILE \
	--fastq $FASTQ_FILE \
	--prefix ${DEMULT_PREFIX} \
	--matched-only \
	--compress \
	$MAPPING_FILE
check_file $DEMULT_FILE

COUNT_ALIGN=$((`zcat $DEMULT_FILE | wc -l` - 1))

zcat $DEMULT_FILE | head -1 > $CHRM_ONLY_FILE
zcat $DEMULT_FILE | grep -P 'chrM\t' >> $CHRM_ONLY_FILE
check_file $CHRM_ONLY_FILE
COUNT_CHRM_ONLY=$((`cat $CHRM_ONLY_FILE | wc -l` - 1))

zcat $DEMULT_FILE | head -1 > $MATCH_FILE
zcat $DEMULT_FILE | grep -P 'Matched\tmt_' >> $MATCH_FILE
check_file $MATCH_FILE
COUNT_MATCHED=$((`cat $MATCH_FILE | wc -l` - 1))

COUNT_CHRM=$(($COUNT_CHRM_ONLY+$COUNT_MATCHED))

echo "=> Reads generated: $COUNT_TOTAL"
echo "==> Reads aligned to reference: $COUNT_ALIGN"
echo "===> Reads aligned to chrM: $COUNT_CHRM"
echo "====> Reads matching $SELECT: $COUNT_MATCHED"

if ! [ -e "$DEMULT_SUMMARY_FILE" ] ; then
	echo "Sample Id	Reads generated	Reads aligned to reference	Reads aligned to chrM	Reads matching $SELECT" > $DEMULT_SUMMARY_FILE
	echo "[OK] File $DEMULT_SUMMARY_FILE created (with header)"
fi
echo "$SAMPLE_ID	$COUNT_TOTAL	$COUNT_ALIGN	$COUNT_CHRM	$COUNT_MATCHED" >> $DEMULT_SUMMARY_FILE
echo "[OK] Line added to $DEMULT_SUMMARY_FILE"

$MINIMAP2_BIN -ax map-ont $REF_MT_2KB ${DEMULT_PREFIX}_mt_2kb.fastq.gz > alignment_mt_2kb.sam
$MINIMAP2_BIN -ax map-ont $REF_MT_3KB ${DEMULT_PREFIX}_mt_3kb.fastq.gz > alignment_mt_3kb.sam
$MINIMAP2_BIN -ax map-ont $REF_MT_10KB ${DEMULT_PREFIX}_mt_10kb.fastq.gz > alignment_mt_10kb.sam

. /local/env/envsamtools-1.15.sh
samtools view -b alignment_mt_2kb.sam > alignment_mt_2kb.bam
samtools view -b alignment_mt_3kb.sam > alignment_mt_3kb.bam
samtools view -b alignment_mt_10kb.sam > alignment_mt_10kb.bam
rm *.sam

samtools merge $BAM_FILE alignment_mt_2kb.bam alignment_mt_3kb.bam alignment_mt_10kb.bam
check_file $BAM_FILE
samtools sort $BAM_FILE -o $SORTED_BAM_FILE
samtools index $SORTED_BAM_FILE
check_file $SORTED_BAM_FILE
check_file "$SORTED_BAM_FILE.bai"

cd $OUT_DIR

echo
echo '*******************'
echo '* Variant calling *'
echo '*******************'
echo "TO DO..."

echo
echo '***********************'
echo '* Retrieving raw data *'
echo '***********************'
check_file $MATCH_FILE
cut -f1 $MATCH_FILE | tail -n +2 > $IDS_FILE

. /local/env/envconda.sh
conda activate $MODKIT_ENV

echo "`modkit --version`"
check_dir $POD5_DIR

modkit filter $POD5_DIR --output $DEMULT_POD5_FILE --ids $IDS_FILE --missing-ok

conda deactivate

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
