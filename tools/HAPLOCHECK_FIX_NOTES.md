# Correctifs haplocheck pour VCF Nanopore (état actuel)

## Problème identifié

- Haplocheck attend l'`AF` dans le champ FORMAT (par échantillon). Lorsque l'`AF` n'est présent qu'en INFO, les hétéroplasmiques ne sont pas détectés correctement.
- Certains variants structuraux (indels, délétions) génèrent des champs FORMAT variables qui font échouer le parseur Java de haplocheck.

## Solutions en place

- Injection de `AF` dans FORMAT depuis `HPL` via un script awk dédié.
- Ajout du header FORMAT/AF si manquant (fallback bcftools annotate).
- Filtrage des variants pour haplocheck: SNVs avec statut PASS uniquement, excluant indels/mnps/ref/bnd/other.
- Correction du parsing des sorties haplocheck dans le rapport HTML (gestion des guillemets et des retours ligne inattendus).

## Fichiers concernés

- [wf-demultmt.sh](wf-demultmt.sh): étape d'annotation et préparation VCF; injection `AF` en FORMAT; filtrage des SNVs PASS avant haplocheck.
- [tools/inject_af_to_format.awk](tools/inject_af_to_format.awk): logique d'extraction `HPL` → `AF` FORMAT, avec support multi-allélique.
- [wf-finalize.sh](wf-finalize.sh): robustesse du parsing des tableaux haplocheck pour le rapport HTML.
- [tools/rerun_all_workflows.sh](tools/rerun_all_workflows.sh): relance batch optionnelle pour réappliquer les correctifs sur des runs existants.

## Détails techniques

### Injection `HPL` → `AF` (FORMAT)

Principe: trouver l'index `HPL` dans `FORMAT`, extraire la valeur par échantillon, choisir la valeur maximale en cas multi-allélique, puis ajouter `AF` à FORMAT et aux colonnes échantillon.

Remarque: le workflow ajoute le header FORMAT `AF` si absent pour assurer la conformité VCF.

### Filtrage avant haplocheck

- Conservation des variants `-f PASS` et exclusion des types non-SNV (`-V indels,mnps,ref,bnd,other`).
- Objectif: éviter les FORMAT variables des SV qui provoquent des erreurs de parse.

## Résultats validés (échantillons de test)

- Are: haplogroupe H5a6; contamination détectée ~1.8%; 8 homoplasmies / 4 hétéroplasmiques.
- Imb: haplogroupe U3b; aucune contamination; 22 homoplasmies / 2 hétéroplasmiques.
- Ker: haplogroupe U4b1b1a; aucune contamination; 28 homoplasmies / 0 hétéroplasmiques.

## Notes de compatibilité

- Les exports TSV et HTML restent compatibles; la colonne `AF` est désormais en FORMAT pour haplocheck.
- Aucune hypothèse sur des préfixes d'annotations n'est requise ici; les champs utilisés restent ceux du pipeline courant.

## Tests et relance

Pour relancer des runs avec les correctifs:

```bash
tools/rerun_all_workflows.sh /chemin/vers/racine_runs --only-needing --dry-run
tools/rerun_all_workflows.sh /chemin/vers/racine_runs --only-needing
```

Pour vérifier un VCF annoté (extraits et headers), utiliser directement `bcftools` et inspection manuelle.

## Historique

- Problème initial: échec haplocheck et hétéroplasmiques non détectés lorsque `AF` n'était qu'en INFO.
- Correctifs: `AF` injecté en FORMAT; filtrage SNVs PASS; parsing rapport HTML durci.
