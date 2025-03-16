#!/bin/bash
#SBATCH --job-name=demultmt
#SBATCH --cpus-per-task=12
#SBATCH --mem=150G
#SBATCH --time 30
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_90
#SBATCH --mail-user=marc.ferre@univ-angers.fr
VERSION='25.03.16.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Run id = Working directory
RUN_ID=${PWD##*/} # Assign directory name to run id
RUN_ID=${RUN_ID:-/} # Correct for the case where PWD=/

# Sample id = Argument
if [ $# -eq 0 ]
	then
		echo "[ERROR] No arguments supplied"
		exit 9999 # die with error code 9999
fi
SAMPLE_ID=$1

# Read selection strategy (start, both, either ,xor)
SELECT='both' 

# Directories
RUN_DIR=`pwd`
FASTQ_DIR="$RUN_DIR/fastq_pass/$SAMPLE_ID"
POD5_DIR="$RUN_DIR/pod5"
PROCESS_DIR="$RUN_DIR/processing"
OUT_DIR="$PROCESS_DIR/$SAMPLE_ID"
SELECT_DIR="$OUT_DIR/select-$SELECT"

# Binaries
BALDUR_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/baldur-1.2.2/target/release/baldur'
ONT_DEMULT_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/ont_demult/target/release/ont_demult'

# Conda envs
BALDUR_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_baldur'
ONT_DEMULT_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_ont_demult'
POD5_ENV='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_pod5'

# References
REF_WHOLE='/scratch/mferre/reference/Homo_sapiens-hg38-GRCh38.p14.fa'
REF_MT='/scratch/mferre/reference/chrM.fa'
REF_MT_2KB='/scratch/mferre/reference/chrM-mt_2kb.fa'
REF_MT_3KB='/scratch/mferre/reference/chrM-mt_3kb.fa'
REF_MT_10KB='/scratch/mferre/reference/chrM-mt_10kb.fa'

# Prefixes
BALDUR_PREFIX="$SAMPLE_ID.baldur"
DEMULT_PREFIX="$SAMPLE_ID.ont_demult"

# Files
CUT_FILE='/scratch/mferre/reference/cut.txt'
CUT_TAG='mt_3kb'
DEMULT_SUMMARY_FILE="$PROCESS_DIR/demult_summary.$RUN_ID.tsv"
DEMULT_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.txt.gz"
CHRM_ONLY_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.match_chrM_only.txt"
MATCH_FILE="$SELECT_DIR/${DEMULT_PREFIX}_res.matched.txt"
IDS_FILE="$SELECT_DIR/$SAMPLE_ID.read_ids.txt"
BAM_FILE="$SELECT_DIR/$SAMPLE_ID.bam"
SORTED_BAM_FILE="$SELECT_DIR/$SAMPLE_ID.sorted.bam"
DEMULT_POD5_FILE="$OUT_DIR/$SAMPLE_ID.demultmt.pod5"
WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

check_dir () { 
	if [ -d "$1" ] # && [ ! -z "$( ls -A $1 )" ]
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

echo "Workflow: wf-demultmt v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Sample: $SAMPLE_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run directory: $RUN_DIR"
echo "Pod5 directory: $POD5_DIR"
echo "FastQ directory: $FASTQ_DIR"
echo "Output directory: $OUT_DIR"
echo "Read selection strategy: $SELECT"
echo "Date: `date`"

echo
echo '*****************'
echo '* Preprocessing *'
echo '*****************'
check_dir $FASTQ_DIR
mkdir -p $OUT_DIR
FASTQ_FILE="$OUT_DIR/$SAMPLE_ID.fastq.gz"
echo "FastQ file: $FASTQ_FILE"
MAPPING_FILE="$OUT_DIR/$SAMPLE_ID.paf"
echo "Mapping file: $MAPPING_FILE"

cat $FASTQ_DIR/*.fastq.gz > $FASTQ_FILE
check_file $FASTQ_FILE
COUNT_TOTAL=$(expr $(zcat $FASTQ_FILE|wc -l)/4|bc)

. /local/env/envconda.sh

echo
echo '******************************'
echo '* Mapping Standard Reference *'
echo '******************************'
conda activate $ONT_DEMULT_ENV
echo "Minimap2 version: `minimap2 --version`"

minimap2 -x map-ont -t 10 $REF_WHOLE $FASTQ_FILE > $MAPPING_FILE
check_file $MAPPING_FILE

echo
echo '******************'
echo '* Demultiplexing *'
echo '******************'
echo "`$ONT_DEMULT_BIN --version`"

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
	echo "Run id	Sample id	Reads generated	Reads aligned to reference	Reads aligned to chrM	Reads matching $SELECT" > $DEMULT_SUMMARY_FILE
	echo "[OK] File $DEMULT_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID	$SAMPLE_ID	$COUNT_TOTAL	$COUNT_ALIGN	$COUNT_CHRM	$COUNT_MATCHED" >> $DEMULT_SUMMARY_FILE
echo "[OK] Line added to $DEMULT_SUMMARY_FILE"

minimap2 -ax map-ont $REF_MT_2KB ${DEMULT_PREFIX}_mt_2kb.fastq.gz > alignment_mt_2kb.sam
minimap2 -ax map-ont $REF_MT_3KB ${DEMULT_PREFIX}_mt_3kb.fastq.gz > alignment_mt_3kb.sam
minimap2 -ax map-ont $REF_MT_10KB ${DEMULT_PREFIX}_mt_10kb.fastq.gz > alignment_mt_10kb.sam

echo "`samtools --version`"
samtools view -b alignment_mt_2kb.sam > alignment_mt_2kb.bam
samtools view -b alignment_mt_3kb.sam > alignment_mt_3kb.bam
samtools view -b alignment_mt_10kb.sam > alignment_mt_10kb.bam
rm *.sam

samtools merge $BAM_FILE alignment_mt_2kb.bam alignment_mt_3kb.bam alignment_mt_10kb.bam
check_file $BAM_FILE
# samtools sort $BAM_FILE -o $SORTED_BAM_FILE
# check_file $SORTED_BAM_FILE
# samtools index $SORTED_BAM_FILE
# check_file "${SORTED_BAM_FILE}.bai"

conda deactivate

echo "Remove large files:"
rm -i $FASTQ_FILE && [[ ! -e $FASTQ_FILE ]] && echo "[OK] FastQ file removed: $FASTQ_FILE"
rm -i $MAPPING_FILE && [[ ! -e $MAPPING_FILE ]] && echo "[OK] Mapping file removed: $FASTQ_FILE"

echo
echo '*******************'
echo '* Variant Calling *'
echo '*******************'
cd $OUT_DIR
conda activate $BALDUR_ENV
echo "`$BALDUR_BIN --version`"

# !!!
# BUG: Presumed endless command
# Add "&" to fix
$BALDUR_BIN --mapq-threshold 20 \
	--qual-threshold 10 \
	--max-qual 30 \
	--max-indel-qual 20 \
	--homopolymer-limit 4 \
	--reference $REF_MT \
	--adjust 5 \
	--view \
	--output-deletions \
	--output-prefix $BALDUR_PREFIX \
	--sample $SAMPLE_ID \
	$BAM_FILE &

conda deactivate

#check_file "$BALDUR_PREFIX.vcf.gz"
echo "[WARNING] Bug fixed appending '&' to baldur command : no check_file"

echo
echo '***********************'
echo '* Retrieving Raw Data *'
echo '***********************'
check_file $MATCH_FILE

echo "Retrieving matching reads (select: $SELECT)..."
cut -f1 $MATCH_FILE | tail -n +2 > $IDS_FILE
check_file $IDS_FILE

# conda activate $POD5_ENV
# 
# check_dir $POD5_DIR
# 
# pod5 filter $POD5_DIR --output $DEMULT_POD5_FILE --ids $IDS_FILE --missing-ok
# 
# check_file $DEMULT_POD5_FILE
# echo "[WARNING] Option '--missing-ok' to pod5 command: possibly missing reads"
# 
# conda deactivate

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
	echo "Run id	Sample id	Workflow	Runtime (hh:mm)	Status" > $WORKFLOW_SUMMARY_FILE
	echo "[OK] File $WORKFLOW_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID	$SAMPLE_ID	demultmt	$HOURS:$MINUTES	[OK]" >> $WORKFLOW_SUMMARY_FILE
echo "[OK] Line added to $WORKFLOW_SUMMARY_FILE"
