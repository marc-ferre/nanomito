#!/bin/bash
#SBATCH --job-name=bchg
#SBATCH --gpus=1
#SBATCH --partition=gpu
#SBATCH --cpus-per-task=12
#SBATCH --mem=50G
#SBATCH --time 2-00:00:00
#SBATCH --mail-type=END,FAIL,INVALID_DEPEND,REQUEUE,STAGE_OUT,TIME_LIMIT_80
#SBATCH --mail-user=marc.ferre@univ-angers.fr
#
#
# wf-bchg.sh /Path/to/run/dir/
#
#
VERSION='25.10.26.1'

AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

# Directories
RUN_DIR=$(pwd)
POD5_DIR="$RUN_DIR/pod5_chrM"
FASTQ_DIR="$RUN_DIR/fastq_pass"
PROCESS_DIR="$RUN_DIR/processing"

# Prefixes
RUN_ID=$(basename "$RUN_DIR")

# Files - Version robuste avec gestion de multiples sample_sheet
SAMPLESHEET_FILES=($(find "$RUN_DIR" -maxdepth 2 -type f -name 'sample_sheet_*.csv'))

if [ ${#SAMPLESHEET_FILES[@]} -eq 0 ]; then
    echo "[ERROR] No sample_sheet_*.csv file found in $RUN_DIR or subdirectories"
    echo "Looking for files matching: sample_sheet_*.csv"
    echo "Available CSV files:"
    find "$RUN_DIR" -maxdepth 2 -type f -name '*.csv'
    exit 128
elif [ ${#SAMPLESHEET_FILES[@]} -eq 1 ]; then
    SAMPLESHEET_FILE=$(readlink -f "${SAMPLESHEET_FILES[0]}")
    echo "[OK] Found 1 sample_sheet file: $SAMPLESHEET_FILE"
else
    echo "[WARNING] Found ${#SAMPLESHEET_FILES[@]} sample_sheet files:"
    for file in "${SAMPLESHEET_FILES[@]}"; do
        echo "  - $file"
    done
    
    # Vérifier si tous les fichiers ont le même contenu
    FIRST_FILE="${SAMPLESHEET_FILES[0]}"
    ALL_IDENTICAL=true
    
    for ((i=1; i<${#SAMPLESHEET_FILES[@]}; i++)); do
        if ! cmp -s "$FIRST_FILE" "${SAMPLESHEET_FILES[$i]}"; then
            ALL_IDENTICAL=false
            echo "[ERROR] Sample sheet files have different content:"
            echo "  - $FIRST_FILE"
            echo "  - ${SAMPLESHEET_FILES[$i]}"
            echo "Please keep only one sample_sheet file or ensure they are identical."
            exit 128
        fi
    done
    
    if [ "$ALL_IDENTICAL" = true ]; then
        echo "[OK] All sample_sheet files have identical content"
        # Sélectionner le fichier le plus ancien (première création)
        OLDEST_FILE="${SAMPLESHEET_FILES[0]}"
        for file in "${SAMPLESHEET_FILES[@]}"; do
            if [ "$file" -ot "$OLDEST_FILE" ]; then
                OLDEST_FILE="$file"
            fi
        done
        SAMPLESHEET_FILE=$(readlink -f "$OLDEST_FILE")
        echo "[OK] Using oldest file: $SAMPLESHEET_FILE"
    fi
fi

WORKFLOW_SUMMARY_FILE="$PROCESS_DIR/workflows_summary.$RUN_ID.tsv"

# Basecalling options
MODEL='sup'
KIT='SQK-NBD114-24'

# Binary and Conda env
DORADO_BIN='/home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/dorado'

check_dir () { 
	if [ -d "$1" ]
	then 
   		echo "[OK] Directory $1 exists"
   	else
		echo "[ERROR] Directory $1 doesn't exist"
		exit 128 # die with error code
	fi
}
check_file () { 
	if [ -f "$1" ] && [ -s "$1" ]
	then 
   		echo "[OK] File $1 exists and is not empty"
   	else
		echo "[ERROR] File $1 is empty or doesn't exist"
		exit 128 # die with error code
	fi
}

START=$(date +%s)

echo "Workflow: wf-bchg v.$VERSION by $AUTHOR"
echo "Run: $RUN_ID"
echo "Job: $SLURM_JOB_ID"
echo "Run dir  : $RUN_DIR"
echo "Pod5 dir : $POD5_DIR"
echo "FastQ dir: $FASTQ_DIR"
echo "Sample sheet: $SAMPLESHEET_FILE"
echo "Model: $MODEL"
echo "Kit  : $KIT"
echo "Date : $(date)"

echo
echo '*****************************************'
echo '* Basecalling w/ Barcode Classification *'
echo '*****************************************'

# To work around the issue https://github.com/nanoporetech/dorado/issues/432
export LC_ALL=en_US.UTF-8

check_dir "$POD5_DIR"
check_file "$SAMPLESHEET_FILE"
echo "============= Sample Sheet ============="
column -s, -t < "$SAMPLESHEET_FILE"
echo "========================================"

mkdir -p  "$PROCESS_DIR"
mkdir -p "$FASTQ_DIR"
check_dir "$FASTQ_DIR"

echo "Dorado version:"
$DORADO_BIN --version

$DORADO_BIN basecaller $MODEL "$POD5_DIR" --recursive \
	--sample-sheet "$SAMPLESHEET_FILE" \
	| $DORADO_BIN demux \
	--kit-name $KIT \
	--sample-sheet "$SAMPLESHEET_FILE" \
	--emit-fastq \
	--output-dir "$FASTQ_DIR"

echo
echo "Gzip all files in dir $FASTQ_DIR"
gzip "$FASTQ_DIR"/*.fastq
echo
echo "Organizing files in sample dir in dir $FASTQ_DIR"
cd "$FASTQ_DIR" || exit
for FILE in *.fastq.gz; do
	[[ -e "$FILE" ]] || break  # handle the case of no *.fastq.gz files
	DIR=${FILE#*_}
	DIR=${DIR%%.*}
	mkdir -p "$DIR"
	mv "$FILE" "$FASTQ_DIR"/"$DIR"/"$FILE"
done

echo
echo '***********'
echo '* Ending  *'
echo '***********'

END=$(date +%s)
RUNTIME=$((END - START))
HOURS=$((RUNTIME / 3600))
MINUTES=$(( (RUNTIME % 3600) / 60 ))
SECONDS=$(( (RUNTIME % 3600) % 60 ))
echo "Runtime: $HOURS:$MINUTES:$SECONDS (hh:mm:ss)"

# Write workflow summary file
if ! [ -e "$WORKFLOW_SUMMARY_FILE" ] ; then
	echo "Run id	Sample id	Workflow	Runtime (hh:mm:ss)" > "$WORKFLOW_SUMMARY_FILE"
	echo "[OK] File $WORKFLOW_SUMMARY_FILE created (with header)"
fi
echo "$RUN_ID	NA	bchg	$HOURS:$MINUTES:$SECONDS" >> "$WORKFLOW_SUMMARY_FILE"
echo "[OK] Line added to $WORKFLOW_SUMMARY_FILE"
