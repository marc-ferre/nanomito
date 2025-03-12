#!/bin/bash
#SBATCH --job-name=Migration
#SBATCH --constraint avx2
#SBATCH --mail-type=ALL
#SBATCH --mail-user=marc.ferre@univ-angers.fr

VERSION='2024-12.07.1'
AUTHOR='Marc FERRE <marc.ferre@univ-angers.fr>'

START=`date +%s`

echo "Workflow: migration_to_new_storage v.$VERSION by $AUTHOR"
echo "Job: $SLURM_JOB_ID"
echo "Date: `date`"

echo
echo '*************'
echo '* Starting  *'
echo '*************'

# Copy data from old (/groups) to new storage (/projects)
rsync -av --stats --progress --delete /groups/nanomito/ /projects/nanomito/

# Copy data from old scratch (/scratch) to new storage (/scratch-new)
rsync -av --stats --progress --delete /scratch/mferre/ /scratch-new/mferre/

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