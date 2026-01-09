# Correctifs haplocheck pour VCF Nanopore

## Architecture actuelle

Le workflow nanomito génère désormais deux types de VCF:

1. **`SAMPLE_ID.ann.vcf`** (fichier principal)
   - Annotations complètes MitoMap et gnomAD (avec préfixes `MitoMap_` et `gnomAD_`)
   - Tous les variants (SNVs, indels, délétions)
   - Pas de champ `AF` en FORMAT
   - Export TSV correspondant: `SAMPLE_ID.ann.tsv`

2. **`haplo/SAMPLE_ID.haplo.vcf`** (spécifique haplocheck)
   - Sous-répertoire dédié: `processing/SAMPLE_ID/haplo/`
   - Filtré: PASS SNVs uniquement (exclut indels, mnps, ref, bnd, other)
   - Champ `AF` ajouté en FORMAT (extrait depuis `HPL`)
   - Header `##FORMAT=<ID=AF,...>` injecté via bcftools
   - Utilisé uniquement par haplocheck

## Problème résolu

Haplocheck requiert l'`AF` dans le champ FORMAT (per-sample) pour détecter correctement les hétéroplasmies. Les variants structuraux (indels, délétions) causaient des erreurs de parsing dans haplocheck.

## Solutions implémentées

### Séparation des VCF

- Le fichier `.ann.vcf` principal reste intact (pas d'`AF`)
- Un VCF dédié `.haplo.vcf` est créé dans `haplo/` pour haplocheck uniquement

### Pipeline haplocheck

1. Filtrage: `bcftools view -f PASS -V indels,mnps,ref,bnd,other` du fichier `.ann.vcf`
2. Injection `AF`: script AWK extrait `HPL` → `AF` en FORMAT
3. Header: `bcftools annotate` ajoute `##FORMAT=<ID=AF,...>`
4. Exécution: `haplocheck --raw --out haplo/SAMPLE_ID-haplocheck haplo/SAMPLE_ID.haplo.vcf`

### Organisation des fichiers

```
processing/SAMPLE_ID/
├── SAMPLE_ID.ann.vcf              # VCF principal avec annotations MitoMap/gnomAD
├── SAMPLE_ID.ann.tsv              # Export TSV
└── haplo/                         # Répertoire haplocheck
    ├── SAMPLE_ID.haplo.vcf        # VCF filtré avec AF pour haplocheck
    └── SAMPLE_ID-haplocheck.raw.txt  # Résultats haplocheck
```

Le fichier de synthèse global `haplocheck_summary.RUN_ID.tsv` reste dans `processing/`.

## Fichiers concernés

- [wf-demultmt.sh](../wf-demultmt.sh): création du répertoire `haplo/`, génération du VCF haplocheck, exécution haplocheck
- [tools/inject_af_to_format.awk](inject_af_to_format.awk): extraction `HPL` → `AF` FORMAT avec support multi-allélique
- [wf-finalize.sh](../wf-finalize.sh): parsing robuste des tableaux haplocheck dans les rapports HTML

## Détails techniques

### Injection `HPL` → `AF` (FORMAT)

Le script AWK:
1. Trouve l'index `HPL` dans le champ FORMAT
2. Extrait la valeur `HPL` pour chaque échantillon
3. En cas multi-allélique, prend la valeur maximale
4. Ajoute `AF` au champ FORMAT et aux colonnes échantillon
5. Ajoute le header `##FORMAT=<ID=AF,...>` si absent

Ensuite, `bcftools annotate -h` force l'ajout du header (sécurité).

### Filtrage pour haplocheck

```bash
bcftools view -f PASS -V indels,mnps,ref,bnd,other
```

- Conserve uniquement les variants SNV avec statut PASS
- Évite les erreurs de parsing dues aux variants structuraux
- Réduit la taille du VCF pour améliorer les performances

## Résultats validés (échantillons de test)

| Sample | Haplogroupe | Contamination | Homoplasmies | Hétéroplasmies |
|--------|-------------|---------------|--------------|----------------|
| Are | H5a6 | ~1.8% | 8 | 4 |
| Imb | U3b | Aucune | 22 | 2 |
| Ker | U4b1b1a | Aucune | 28 | 0 |

## Tests et relance

Pour relancer des runs avec la nouvelle architecture:

```bash
# Dry-run pour vérifier les runs nécessitant un retraitement
tools/rerun_all_workflows.sh /chemin/vers/racine_runs --only-needing --dry-run

# Relance effective
tools/rerun_all_workflows.sh /chemin/vers/racine_runs --only-needing
```

Pour vérifier un VCF haplocheck:

```bash
# Vérifier le header AF
bcftools view -h processing/SAMPLE_ID/haplo/SAMPLE_ID.haplo.vcf | grep "^##FORMAT=<ID=AF"

# Vérifier les valeurs AF dans FORMAT
bcftools view processing/SAMPLE_ID/haplo/SAMPLE_ID.haplo.vcf | grep -v "^#" | head -5
```

## Historique

- **v2.2.x**: Tentatives d'injection `AF` dans le fichier `.ann.vcf` principal
- **v2.3.0**: Restructuration avec séparation claire `.ann.vcf` vs `.haplo.vcf` dans sous-répertoire dédié
