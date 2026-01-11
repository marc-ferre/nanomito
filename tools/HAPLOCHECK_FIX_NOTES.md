# Haplocheck fixes for Nanopore VCFs

## Current layout

The nanomito workflow now produces two VCF files:

1. **`SAMPLE_ID.ann.vcf`** (main file)
   - Full MitoMap and gnomAD annotations (prefixed `MitoMap_` and `gnomAD_`)
   - All variants (SNVs, indels, deletions)
   - No `AF` field in FORMAT
   - TSV export: `SAMPLE_ID.ann.tsv`

2. **`haplo/SAMPLE_ID.haplo.vcf`** (haplocheck-specific)
   - Dedicated subdirectory: `processing/SAMPLE_ID/haplo/`
   - Filtered: PASS SNVs only (excludes indels, mnps, ref, bnd, other)
   - `AF` field added in FORMAT (extracted from `HPL`)
   - Header `##FORMAT=<ID=AF,...>` injected via bcftools
   - Used only by haplocheck

## Problem addressed

Haplocheck expects `AF` in the FORMAT field (per-sample) to detect heteroplasmies. Structural variants (indels, deletions) triggered parsing errors in haplocheck.

## Implemented solutions

### Split VCFs

- The main `.ann.vcf` stays unchanged (no `AF` injected)
- A dedicated `.haplo.vcf` is created in `haplo/` for haplocheck only

### Haplocheck pipeline

1. Filtering: `bcftools view -f PASS -V indels,mnps,ref,bnd,other` from the `.ann.vcf`
2. `AF` injection: AWK extracts `HPL` → `AF` in FORMAT
3. Header: `bcftools annotate` adds `##FORMAT=<ID=AF,...>`
4. Execution: `haplocheck --raw --out haplo/SAMPLE_ID-haplocheck haplo/SAMPLE_ID.haplo.vcf`

### File layout

```text
processing/SAMPLE_ID/
├── SAMPLE_ID.ann.vcf              # Main VCF with MitoMap/gnomAD annotations
├── SAMPLE_ID.ann.tsv              # TSV export
└── haplo/                         # Haplocheck directory
    ├── SAMPLE_ID.haplo.vcf        # Filtered VCF with AF for haplocheck
    └── SAMPLE_ID-haplocheck.raw.txt  # Haplocheck results
```

The consolidated summary file `haplocheck_summary.RUN_ID.tsv` remains in `processing/`.

## Touched files

- [wf-demultmt.sh](../wf-demultmt.sh): creates `haplo/`, generates the haplocheck VCF, runs haplocheck
- [tools/inject_af_to_format.awk](inject_af_to_format.awk): extracts `HPL` → `AF` in FORMAT with multi-allelic support
- [wf-finalize.sh](../wf-finalize.sh): robust parsing of haplocheck tables in HTML reports

## Technical details

### `HPL` → `AF` injection (FORMAT)

The AWK script:

1. Finds the `HPL` index in the FORMAT field
2. Extracts the `HPL` value for each sample
3. Takes the maximum value when multi-allelic
4. Appends `AF` to FORMAT and to sample columns
5. Adds the header `##FORMAT=<ID=AF,...>` if missing

Then `bcftools annotate -h` forces the header addition as a safeguard.

### Filtering for haplocheck

```bash
bcftools view -f PASS -V indels,mnps,ref,bnd,other
```

- Keeps PASS SNVs only
- Avoids parsing errors from structural variants
- Reduces VCF size for faster processing

## Validated results (test samples)

| Sample | Haplogroup | Contamination | Homoplasmies | Heteroplasmies |
| ------ | ---------- | ------------- | ------------ | -------------- |
| Are    | H5a6       | ~1.8%         | 8            | 4              |
| Imb    | U3b        | None          | 22           | 2              |
| Ker    | U4b1b1a    | None          | 28           | 0              |

## Tests and reruns

To rerun with the new layout:

```bash
# Dry-run to see which runs need reprocessing
tools/rerun_all_workflows.sh /path/to/runs_root --only-needing --dry-run

# Actual rerun
tools/rerun_all_workflows.sh /path/to/runs_root --only-needing
```

To check a haplocheck VCF:

```bash
# Confirm AF header
bcftools view -h processing/SAMPLE_ID/haplo/SAMPLE_ID.haplo.vcf | grep "^##FORMAT=<ID=AF"

# Inspect AF values in FORMAT
bcftools view processing/SAMPLE_ID/haplo/SAMPLE_ID.haplo.vcf | grep -v "^#" | head -5
```

## History

- **v2.2.x**: Attempted `AF` injection into the main `.ann.vcf`
- **v2.3.0**: Clear split between `.ann.vcf` and `.haplo.vcf` in a dedicated subdirectory
