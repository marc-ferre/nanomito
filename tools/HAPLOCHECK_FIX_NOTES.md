# Modifications pour corriger le problème haplocheck avec les VCF Nanopore

## Problème identifié

Haplocheck produit des haplogroupes incorrects pour les fichiers VCF Nanopore car :
- Haplocheck s'attend à trouver le taux d'hétéroplasmie dans le tag `AF` du champ INFO
- Les VCF Nanopore stockent l'hétéroplasmie dans le tag `HPL` du champ FORMAT

## Solution mise en œuvre

### 1. Préfixage des tags d'annotation

Pour éviter les conflits de noms entre les différentes bases de données, tous les tags sont maintenant préfixés :
- Tags MITOMAP : préfixe `MitoMap_` (ex: `MitoMap_Disease`, `MitoMap_AC`, etc.)
- Tags gnomAD : préfixe `gnomAD_` (ex: `gnomAD_AC_het`, `gnomAD_AF_het`, etc.)

### 2. Création du tag AF dans INFO

Un nouveau tag `AF` est créé dans le champ INFO en extrayant la valeur de `HPL` du champ FORMAT.
Pour les sites multi-alléliques, la valeur maximale de HPL est utilisée.

## Fichiers modifiés

### Scripts principaux

1. **wf-demultmt.sh** (lignes ~635-702)
   - Ajout de `-name MitoMap_` aux annotations MITOMAP Disease et Polymorphisms
   - Ajout de `-name gnomAD_` à l'annotation gnomAD
   - Création du tag AF depuis HPL avec un script awk
   - Mise à jour de l'export TSV avec les nouveaux noms de colonnes préfixés

2. **tools/compare_vcf.sh**
   - Fonction `annotate_vcf()` (lignes ~67-100)
     * Ajout des préfixes pour les annotations
     * Création du tag AF (supporte HPL pour Nanopore et AF pour Illumina)
   - Fonction `export_vcf_to_tsv_Illumina()` (lignes ~739-752)
     * Mise à jour des headers et bcftools query avec préfixes
   - Fonction `export_vcf_to_tsv_Nanopore()` (lignes ~754-772)
     * Mise à jour des headers et bcftools query avec préfixes

3. **wf-finalize.sh** (lignes ~640-655)
   - Mise à jour de la génération TSV pour le rapport HTML
   - Headers et bcftools query avec les nouveaux préfixes

### Scripts de diagnostic et correction

4. **tools/test_haplocheck_vcf.sh** (nouveau)
   - Script de diagnostic pour vérifier la structure d'un VCF
   - Détecte la présence de HPL et AF
   - Affiche des exemples de données

5. **tools/fix_vcf_for_haplocheck.sh** (nouveau)
   - Script pour corriger un VCF existant
   - Renomme AF existant en AF_gnomAD
   - Crée un nouveau tag AF depuis HPL
   - Usage: `./fix_vcf_for_haplocheck.sh input.vcf output.vcf`

6. **tools/test_haplocheck_fix.sh** (nouveau)
   - Script de test complet
   - Applique le fix et exécute haplocheck
   - Compare les résultats avant/après
   - Usage: `./test_haplocheck_fix.sh input.vcf [haplocheck.jar]`

## Détails techniques

### Extraction de HPL vers AF

Exemple awk (utilisé dans le workflow) pour créer le tag AF à partir du champ FORMAT/HPL. Il préfixe le champ INFO en ajoutant AF au début et gère les sites multi-alléliques en prenant la valeur maximale.

```bash
awk '
BEGIN {OFS="\t"}
/^#/ {print; next}
{
    split($9, fmt, ":")
    hpl_idx = 0
    for (i=1; i<=length(fmt); i++) {
        if (fmt[i] == "HPL") {
            hpl_idx = i
            break
        }
    }
    
    if (hpl_idx > 0) {
        split($10, vals, ":")
        hpl_value = vals[hpl_idx]
        
        # Handle multi-allelic: take max value
        if (index(hpl_value, ",") > 0) {
            n = split(hpl_value, hpl_arr, ",")
            max_hpl = hpl_arr[1] + 0
            for (i=2; i<=n; i++) {
                v = hpl_arr[i] + 0
                if (v > max_hpl) max_hpl = v
            }
            hpl_value = max_hpl
        }
        
        # Prepend AF tag to INFO field
        if ($8 == "." || $8 == "") {
            $8 = "AF=" hpl_value
        } else {
            $8 = "AF=" hpl_value ";" $8
        }
    }
    print
}' input.vcf
```

### Nouveaux noms de colonnes TSV

Avant :
```
CHROM POS ID REF ALT HPL AC AF Disease DiseaseStatus ...
```

Après :
```
CHROM POS ID REF ALT HPL AF MitoMap_AC MitoMap_AF MitoMap_Disease MitoMap_DiseaseStatus ...
gnomAD_AC_het gnomAD_AC_hom gnomAD_AF_het gnomAD_AF_hom ...
```

## Test

Pour tester sur un fichier existant :

```bash
cd /Users/marcferre/Documents/Recherche/Projets/Nanomito/GitHub/nanomito/tools

# Test simple
./test_haplocheck_vcf.sh /path/to/your.vcf

# Test complet avec haplocheck
./test_haplocheck_fix.sh /path/to/your.ann.vcf

# Correction manuelle d'un fichier
./fix_vcf_for_haplocheck.sh input.vcf output.vcf
```

## Rétrocompatibilité

⚠️ **ATTENTION** : Ces modifications changent les noms de colonnes dans les fichiers TSV générés.

- Les anciens scripts ou analyses qui font référence aux colonnes `AC`, `AF`, `Disease`, etc. devront être mis à jour
- Les nouveaux noms sont `MitoMap_AC`, `MitoMap_AF`, `MitoMap_Disease`, `gnomAD_AC_het`, etc.
- La colonne `HPL` reste inchangée (format Nanopore)
- Une nouvelle colonne `AF` est créée dans INFO (pour haplocheck)

Note: Dans le workflow mis à jour, les tags des bases de données sont préfixés (`MitoMap_*`, `gnomAD_*`) donc il n’y a plus de conflit sur `AF` provenant des annotations. Le script standalone `fix_vcf_for_haplocheck.sh` gère le cas d’un VCF déjà annoté sans préfixes en renommant `INFO/AF` existant en `INFO/AF_gnomAD` et en ajoutant un nouveau `INFO/AF` dérivé de l’échantillon.

## Prochaines étapes

1. Tester les modifications sur un fichier Nanopore réel
2. Vérifier que haplocheck produit maintenant les bons haplogroupes
3. Mettre à jour tout script externe qui analyse les TSV générés
4. Documenter le changement dans le CHANGELOG

## Références

- Issue: Haplogroup incorrect pour fichiers Nanopore
- Date: 2026-01-01
- Solution: Préfixage des annotations + création tag AF depuis HPL
