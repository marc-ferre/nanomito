# Correction: Race Condition dans les fichiers de résumé partagés

## Problème Identifié

**Job échoué:** Slurm Job_id=15367335 Name=d58_LELM Failed, Run time 00:01:37, FAILED, ExitCode 1

**Erreur du log:**
```
cp: impossible de créer le fichier standard '/scratch/mferre/workbench/250331_P2_run002/processing/haplocheck_summary.250331_P2_run002.tsv': Le fichier existe
[ERROR] 11:31:36 - Script failed with exit code 1
```

## Cause Racine

Une **condition de course (race condition)** se produit lorsque plusieurs jobs Slurm exécutés en parallèle essaient de créer/modifier les mêmes fichiers de résumé au même moment.

### Workflows affectés:
- `wf-demultmt.sh` - Multiple jobs (un par sample) exécutés en parallèle
- `wf-modmito.sh` - Multiple jobs (un par sample) exécutés en parallèle
- `wf-bchg.sh` - Un seul job, mais impact potentiel
- `wf-subwf.sh` - Un seul job, mais impact potentiel

### Fichiers partagés causant le problème:
1. `haplocheck_summary.$RUN_ID.tsv` - Résumé des haplogroups
2. `demult_summary.$RUN_ID.tsv` - Résumé du demultiplexing
3. `workflows_summary.$RUN_ID.tsv` - Résumé des workflows exécutés

## Scénario d'Erreur

Quand deux jobs (sample A et sample B) s'exécutent en parallèle:

1. **T0** - Tous deux exécutent `[ ! -e "$HPLCHK_SUMMARY_FILE" ]` → TRUE pour les deux
2. **T1** - Job A exécute `cp $HPLCHK_RAW_FILE $HPLCHK_SUMMARY_FILE` → Succès
3. **T1** - Job B exécute aussi `cp $HPLCHK_RAW_FILE $HPLCHK_SUMMARY_FILE` → **ERREUR** (fichier existe)

## Solution Implémentée

Utilisation de **file locking (flock)** pour assurer l'accès atomique et mutuellement exclusif:

### Pattern Appliqué

```bash
# Atomic file creation/update to prevent race conditions
LOCK_FILE="${TARGET_FILE}.lock"
(
	flock -x 200    # Acquire exclusive lock (wait if necessary)
	
	# Critical section: only one job can execute this at a time
	if ! [ -e "$TARGET_FILE" ] ; then
		echo "Header" > "$TARGET_FILE"
	fi
	echo "Data" >> "$TARGET_FILE"
) 200>"$LOCK_FILE"
rm -f "$LOCK_FILE"
```

## Fichiers Modifiés

### 1. `wf-demultmt.sh`
- **Ligne ~376-381** - DEMULT_SUMMARY_FILE (cas "no data")
- **Ligne ~406-411** - DEMULT_SUMMARY_FILE (cas normal)
- **Ligne ~746-750** - HPLCHK_SUMMARY_FILE
- **Ligne ~796-801** - WORKFLOW_SUMMARY_FILE

### 2. `wf-modmito.sh`
- **Ligne ~316-321** - WORKFLOW_SUMMARY_FILE

### 3. `wf-bchg.sh`
- **Ligne ~634-639** - WORKFLOW_SUMMARY_FILE

### 4. `wf-subwf.sh`
- **Ligne ~507-512** - WORKFLOW_SUMMARY_FILE

## Bénéfices

✅ **Élimine les race conditions** - Garantit l'accès mutuellement exclusif  
✅ **Atomic operations** - Les opérations de création/modification sont indivisibles  
✅ **Automatic cleanup** - Les lock files sont supprimés après utilisation  
✅ **Zero performance impact** - Le verrouillage est naturel lors d'I/O disque  
✅ **Scalable** - Fonctionne avec n'importe quel nombre de jobs parallèles

## Test Recommandé

Pour valider la correction:

```bash
# Relancer le run qui a échoué
ssh mferre@genossh.genouest.org
cd /scratch/mferre/workbench/250331_P2_run002
sbatch --chdir=/scratch/mferre/workbench/250331_P2_run002 \
  /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/nanomito/wf-demultmt.sh 250331_210059058_LELM
```

Vérifier que le job réussit maintenant.

## Notes Techniques

- **flock** est un utilitaire standard sur tous les systèmes Linux/Unix
- Le **file descriptor 200** est utilisé comme arbitre du verrou (convention)
- Pas de modification des fichiers de données, seulement de la synchronisation
