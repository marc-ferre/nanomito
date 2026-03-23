# Nanomito

Comprehensive SLURM workflows for full-length single-molecule sequencing of mitochondrial DNA using Oxford Nanopore Technology.

## Overview

Nanomito is a collection of production-ready bash scripts designed for high-throughput processing of Oxford Nanopore sequencing data, specifically optimized for mitochondrial DNA analysis. The workflows are designed to run on HPC clusters using SLURM workload manager.

### License & Configuration

- Licensed under CeCILL-2.1 (see LICENSE).
- Copy nanomito.config.template to nanomito.config and preprocessing/preprocessing.config.template to preprocessing/preprocessing.config, then set your paths, conda envs, and mail recipient.
- For public releases, keep personalized configuration values out of Git history and commit only template/example files.

### Public Release Checklist

Before publishing this repository or submitting associated manuscript material:

- Verify all runtime and local paths are generic placeholders (no personal workstation paths).
- Ensure sensitive/local configuration values are stored only in local files, not committed tracked config files.
- Remove generated test artifacts that embed absolute local paths in logs or VCF metadata.
- Confirm script headers include SPDX license and author metadata consistently.
- Re-run documentation review for option/feature consistency with current behavior.

### Key Features

- 🧬 **Full mitochondrial genome sequencing** - Complete workflow from basecalling to modification analysis
- 🚀 **GPU-accelerated basecalling** - Leverages Dorado for high-accuracy basecalling with modification detection
- 🔀 **Sample demultiplexing** - Automated barcode demultiplexing and patient-level separation
- 🔬 **Modification detection** - 5mC, 5hmC, and 6mA base modification calling
- 📊 **SLURM integration** - Optimized for HPC environments with automatic job dependency management
- 📦 **Automated archiving** - Integrated archiving to project storage with dependency management
- **Optional export packaging** - Post-run export to $HOME/export (per-sample results + ZIP)
- **HTML email reports** - Beautiful responsive HTML email notifications with comprehensive summaries
- 📄 **Per-sample HTML reports** - Interactive individual reports with variants filtering and disease coloring
- ✅ **Robust error handling** - Comprehensive logging and error recovery mechanisms

### Troubleshooting: Haplocheck (Nanopore VCFs)

**Issue**: Haplocheck reports zero heteroplasmies or fails on specific samples.

**Root causes**:

- `AF` must be in FORMAT field (per-sample), not INFO
- Structural variants (indels/deletions) cause parsing errors

**Current solution (v2.3.0+)**:

The pipeline now maintains **two separate VCF files**:

1. **`SAMPLE_ID.ann.vcf`** (main file)
   - Complete annotations: MitoMap and gnomAD with prefixes
   - All variants (SNVs, indels, deletions)
   - No AF field - clean annotation file

2. **`haplo/SAMPLE_ID.haplo.vcf`** (haplocheck-specific)
   - Dedicated subdirectory: `processing/SAMPLE_ID/haplo/`
   - Filtered: PASS SNVs only (excludes indels, structural variants)
   - AF added to FORMAT field (extracted from HPL)
   - Header `##FORMAT=<ID=AF,...>` injected via bcftools

All haplocheck outputs are stored in the `haplo/` subdirectory for clear separation.

**Batch re-run helper**: Use [tools/rerun_all_workflows.sh](tools/rerun_all_workflows.sh) to reprocess runs:

```bash
tools/rerun_all_workflows.sh /path/to/runs --only-needing --dry-run
tools/rerun_all_workflows.sh /path/to/runs --only-needing
```

**Full details**: [tools/HAPLOCHECK_FIX_NOTES.md](tools/HAPLOCHECK_FIX_NOTES.md)

### Troubleshooting: Barcodes & Sample Sheet

- Windows CSV (CRLF) files are still supported, but they can break aliases if `\r` is not removed.
- The pipeline now strips `\r` from barcodes/aliases in `wf-bchg.sh`, but ideally convert the sheet before import: `dos2unix sample_sheet*.csv`.
- Expected columns: `barcode` and `alias` (plus `kit`, `experiment_id`, `flow_cell_id`, or `position_id`).
- Quick diagnostics: `tools/diagnose_samplesheet.sh /path/to/run` lists the columns and the detected mappings.

### Dorado Models (basecalling & mods)

- Configure the models in `nanomito.config`:
  - `DORADO_MODEL='sup'` (wf-bchg)
  - `DORADO_MODEL_COMPLEX='sup,5mC_5hmC,6mA'` (wf-modmito)
- If Dorado returns `No matches for chemistry...mods_variant`, switch to the basic model: `DORADO_MODEL_COMPLEX='sup'`.
- Make sure the installed Dorado version provides the requested model (`dorado --version`, then `dorado download model ...`).

## Workflow Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                     submit_nanomito.sh                          │
│        Main workflow submission orchestrator with options       │
│  --bchg-only / --skip-bchg / --demultmt-only / --modmito-only   │
│  --skip-demultmt / --skip-modmito / --archiving-only /          │
│                   --skip-archiving / --finalize-only            │
└──────────────────┬──────────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
┌───────────────┐     ┌──────────────┐
│  wf-bchg.sh   │     │ wf-subwf.sh  │
│  Basecalling  │────▶│ Discovers    │
│  & Demux      │     │ samples      │
└───────────────┘     └──────┬───────┘
                             │
                ┌────────────┴────────────┐
                ▼                         ▼
        ┌──────────────┐         ┌──────────────┐
        │wf-demultmt.sh│         │wf-modmito.sh │
        │ MT reads     │────────▶│ Modification │
        │ demultiplex  │         │ analysis     │
        │ (per sample) │         │ (per sample) │
        └──────────────┘         └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │wf-archiving  │
                                 │ Archive data │
                                 │ to project   │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │wf-finalize.sh│
                                 │ HTML email   │
                                 │ report       │
                                 └──────┬───────┘
                                        │
                                        ▼
                                 ┌──────────────┐
                                 │ wf-export.sh │
                                 │ Package &    │
                                 │ ZIP results  │
                                 └──────────────┘
```

**Two-step submission architecture:**

1. `submit_nanomito.sh` submits `wf-bchg.sh` and `wf-subwf.sh`
2. `wf-subwf.sh` waits for basecalling completion, discovers samples, then submits analysis jobs
3. `wf-subwf.sh` also submits a final job (`wf-finalize.sh`) that sends a single notification email when all jobs finish, and optionally schedules `wf-export.sh` after finalization when export is enabled.

This design ensures dynamic sample discovery after basecalling creates the sample directories.

## Workflows Description

### 1. **submit_nanomito.sh**

Main entry point for workflow submission. Orchestrates the entire pipeline by submitting basecalling and the intermediate orchestrator workflow.

**Usage:**

```bash
# Submit complete pipeline (basecalling + analysis)
./submit_nanomito.sh /path/to/run/directory

# Only basecalling and demultiplexing
./submit_nanomito.sh --bchg-only /path/to/run/directory

# Skip basecalling, only submit analysis workflows (for pre-existing FASTQ files)
./submit_nanomito.sh --skip-bchg /path/to/run/directory

# Re-run only demultmt workflows
./submit_nanomito.sh --skip-bchg --demultmt-only /path/to/run/directory

# Re-run only modmito workflows
./submit_nanomito.sh --skip-bchg --modmito-only /path/to/run/directory

# Run full pipeline but skip modmito
./submit_nanomito.sh --skip-modmito /path/to/run/directory

# Include 'unclassified' folder in sample processing (skipped by default)
./submit_nanomito.sh --skip-bchg --include-unclassified /path/to/run/directory

# Process only specific samples (reprocess failed samples without touching successful ones)
./submit_nanomito.sh --only-samples SAMPLE1,SAMPLE2 /path/to/run/directory

# Re-run analysis for specific samples only (skip basecalling)
./submit_nanomito.sh --skip-bchg --only-samples SAMPLE1,SAMPLE2 /path/to/run/directory

# Process all samples including those not in sample sheet (bypass automatic filtering)
./submit_nanomito.sh --all /path/to/run/directory

# Archive data only (without processing)
./submit_nanomito.sh --archiving-only /path/to/run/directory

# Skip archiving in workflow
./submit_nanomito.sh --skip-archiving /path/to/run/directory

# Generate HTML email report only (for testing)
./submit_nanomito.sh --finalize-only /path/to/run/directory

# Display help
./submit_nanomito.sh --help
```

**Options:**

- `--bchg-only` - Only submit basecalling/demux workflow (wf-bchg.sh)
- `--skip-bchg` - Skip basecalling/demux, only submit analysis workflows
- `--demultmt-only` - Only submit demultmt workflow (requires --skip-bchg)
- `--skip-demultmt` - Skip demultmt workflow, only submit modmito
- `--modmito-only` - Only submit modmito workflow (requires --skip-bchg)
- `--skip-modmito` - Skip modmito workflow, only submit demultmt
- `--archiving-only` - Only submit archiving job (archives existing data)
- `--skip-archiving` - Skip archiving step in the workflow
- `--finalize-only` - Only submit finalization job (email report from existing data)
- `--skip-export` - Disable export job after finalization (export is enabled by default)
- `--export-name NAME` - Override export directory/zip name for `wf-export.sh`
- `--include-unclassified` - Include 'unclassified' folder in sample processing (skipped by default)
- `--only-samples SAMPLES` - Process only specified samples (comma-separated list). Final report includes all samples.
- `--all` - Process all discovered samples, including those not declared in sample sheet (bypasses automatic filtering)
- `--help, -h` - Display help message

**Features:**

- Two-step submission architecture for dynamic sample discovery
- Submits `wf-subwf.sh` which discovers samples after basecalling
- **Automatic sample filtering** from sample sheet (only declared barcodes/aliases processed by default)
- Automatically skips 'unclassified' folder (use `--include-unclassified` to process it)
- Integrated archiving workflow (enabled by default, use `--skip-archiving` to disable)
- Optional export workflow after finalization (enabled by default, disable with `--skip-export`, override name with `--export-name`)
- Manages job dependencies automatically (analysis → archiving → finalize)
- Supports selective workflow execution with filtering options
- Validation of option compatibility

### 2. **wf-subwf.sh** (Workflow Orchestrator)

Intermediate orchestrator that dynamically discovers samples and submits analysis jobs.

- Waits for basecalling completion via SLURM dependencies
- Discovers all samples in `fastq_pass/` directory
- **Automatic sample sheet filtering:** Only processes barcodes/aliases declared in `sample_sheet_*.csv` (column 4: alias, column 5: barcode)
- Logs warnings for skipped samples not in sample sheet (helps identify contamination or sequencing errors)
- Bypass filtering with `--all` option to process all discovered samples
- Submits demultmt and modmito jobs for each discovered sample
- Respects filtering options (--demultmt-only, --modmito-only, etc.)
- Creates proper job dependencies between demultmt and modmito
- Submits a final notification job (`wf-finalize.sh`) that depends on all submitted jobs and sends one email at the end
- **Resources:** Minimal (orchestration only, < 1 minute runtime)

### 3. **wf-bchg.sh** (Basecalling & Demultiplexing)

- GPU-accelerated basecalling using Dorado
- Automatic sample demultiplexing by barcodes
- Sample sheet alias mapping for directory organization
- FASTQ compression and organization
- **Resources:** 1 GPU, 6 CPUs, 32GB RAM

### 4. **wf-demultmt.sh** (Mitochondrial Reads Demultiplexing)

- Maps reads to reference genome
- Demultiplexes mitochondrial reads by patient
- Read selection strategies (both/start/either/xor)
- Creates read_id→parent_id dictionary for Pod5 filtering
- **Resources:** 8 CPUs, 100GB RAM

**Note:** This workflow expects a `pid_dict.tsv` file created during preprocessing (see `preprocessing/wf-getmt.sh`) that maps read IDs to their parent IDs for proper Pod5 file filtering.

### 5. **wf-modmito.sh** (Modification Analysis)

- Duplex basecalling with modification calling (5mC, 5hmC, 6mA)
- BAM alignment and sorting
- BedMethyl output generation
- **Resources:** 1 GPU, 6 CPUs, 32GB RAM

### 6. **wf-archiving.sh** (Data Archiving)

- Automated rsync of run data to project storage
- Generates archiving summary with size and duration metrics
- Calculates total archived size in human-readable format
- Creates `archiving_summary.<RUN_ID>.tsv` with metadata
- **Resources:** Minimal (I/O bound, < 10 minutes typical)

### 7. **wf-finalize.sh** (HTML Email Report)

- Submitted automatically after all jobs complete (including archiving)
- Waits for successful completion of all jobs (SLURM `afterok` dependency)
- Generates comprehensive HTML email report with:
  - **Workflow Execution Summary** - All jobs with runtimes in formatted table
  - **Sequencing Run Metrics** - Total reads, passed reads/bases from JSON reports
  - **Per-Sample Results** - Alignment stats, haplogroups, variant counts, output files
  - **Summary Files** - Location and sizes of all summary TSV files
  - **Archiving Summary** - Destination, size, duration, and status of archiving
- **Per-sample HTML reports** - Individual interactive HTML reports for each sample:
  - **Run & Sample Metrics** - Alignment, haplogroup, variants, deletions counts
  - **Haplogroup Table** - Full haplocheck results
  - **Variants Table** - Interactive PASS filter, disease coloring (pathogenic/benign)
  - **Deletions Table** - Baldur deletions with strand information
  - **Output Files** - File sizes and validation status
  - **Logs** - Errors and warnings from processing
  - Saved as `processing/<SAMPLE>/report-<SAMPLE>.html`
  - Can be regenerated independently with `--reports-only` option
- **Responsive design** - Optimized for mobile viewing (iPhone, Android)
- **Color-coded status** - Success (green), warnings (yellow), errors (red)
- Sends email to `MAIL_USER` configured in `nanomito.config`
- If no mailer available, saves HTML to `processing/report.<RUN_ID>.html`

**Usage:**

```bash
# Generate email report and per-sample HTML reports (default behavior)
./submit_nanomito.sh --finalize-only /path/to/run/directory

# Regenerate only per-sample HTML reports (without email)
./wf-finalize.sh --reports-only
```

### 8. **archiving.sh** (Manual archiving)

Manual/interactive wrapper for archiving runs to project storage.

- Prompts for confirmation before overwriting existing archives
- Useful for standalone archiving without full workflow
- Calls `wf-archiving.sh` via sbatch
- **Note:** For automated archiving, use `submit_nanomito.sh` with integrated archiving

### 9. **wf-export.sh** (Result Export)

Optional post-finalization export job that packages key outputs to `$HOME/export/<run_name>` and creates a ZIP archive.

- Export is enabled by default; disable with `--skip-export`
- Uses archived directory when available, otherwise exports from scratch run directory
- Supports custom export name via `--export-name`
- Copies per-sample results (VCF/TSV/BAM/BAI) and HTML reports, then zips the run folder
- Runs after `wf-finalize.sh` to ensure reports and archiving are complete

## Preprocessing Workflows

The `preprocessing/` directory contains **Windows-based preprocessing scripts** that prepare raw Nanopore data on a local PC before uploading to the HPC cluster. These scripts reduce data size by filtering only mitochondrial reads, making the HPC workflow more efficient.

**Purpose:** Prepare data on Windows/WSL before running the main Nanomito HPC workflows

**Platform:** Windows workstation with WSL (Windows Subsystem for Linux)

**Workflow:**

1. `wf-prebchg.ps1` - Dorado basecalling on Windows (GPU-accelerated)
2. `wf-getmt.sh` - Extract chrM reads (WSL)
3. `wf-uplgo.sh` - Upload to HPC cluster (WSL)

See [preprocessing/README.md](preprocessing/README.md) for complete documentation.

### **wf-getmt.sh** (Extract chrM reads from raw data)

This script filters raw Nanopore data to keep only mitochondrial chromosome reads, significantly reducing data size for HPC processing.

**Key features:**

- Analyzes Dorado BAM files to identify reads aligned to chrM
- Creates a read_id→parent_id dictionary (`pid_dict.tsv`) from BAM tags
- Filters Pod5 files to extract only chrM-aligned reads (~90% size reduction)
- **Platform:** Windows Subsystem for Linux (WSL)
- **Usage:** `./preprocessing/wf-getmt.sh [/path/to/run]`

**Key outputs:**

- `pod5_chrM/<RUN_ID>.chrM.pod5` - Filtered Pod5 file with chrM reads only
- `pod5_chrM/<RUN_ID>.pid_dict.tsv` - Read-to-parent ID mapping (required for wf-demultmt.sh)
- `pod5_chrM/<RUN_ID>.chrM_pids.txt` - List of parent read IDs

**Note:** This preprocessing step is required before running `wf-demultmt.sh` to ensure proper read ID mapping when working with minimap2 BAMs (which lack the `pi:Z` parent ID tags present in Dorado BAMs).

## Directory Structure

```text
run_directory/
├── pod5_chrM/                    # POD5 files (chrM reads only)
│   ├── <RUN_ID>.chrM.pod5       # Filtered Pod5 with chrM reads
│   └── <RUN_ID>.pid_dict.tsv    # Read-to-parent ID mapping
├── fastq_pass/                   # Demultiplexed FASTQ files
│   ├── barcode09/
│   ├── barcode10/
│   └── ...
├── processing/                   # Workflow outputs and logs
│   ├── sample_1/
│   │   ├── slurm-sample_1.demultmt.out
│   │   ├── slurm-sample_1.demultmt.err
│   │   ├── slurm-sample_1.modmito.out
│   │   ├── slurm-sample_1.modmito.err
│   │   └── select-both/         # Demultiplexed patient files
│   ├── slurm-<RUN_ID>.bchg.out  # Basecalling log
│   ├── slurm-<RUN_ID>.subwf.out # Orchestrator log
│   ├── slurm-<RUN_ID>.final.out # Finalization job log
│   ├── report.<RUN_ID>.html     # HTML report (if mailer unavailable)
│   └── workflows_summary.<RUN_ID>.tsv    # Runtime summary
└── sample_sheet_*.csv           # ONT sample sheet
```

## Installation & Setup

### Prerequisites

- **SLURM** workload manager
- **Dorado** (GPU basecaller)
- **Conda** environments with:
  - `env_getmt`: pod5, pysam (for preprocessing)
  - `env_ont_demult`: ont_demult tool
  - `env_pod5`: pod5 tools
  - minimap2, samtools, modkit
- **GNU Parallel** (optional, for faster compression)
- **Python 3** with pysam library (for pid_dict creation)

### Installation

1. **Clone the repository:**

   ```bash
   # Generate SSH key if not already done
   ssh-keygen -t ed25519 -C "your.email@domain.com"
   cat ~/.ssh/id_ed25519.pub  # Add this to GitHub Settings > SSH keys

   # Clone the repository
   cd /home/your_username/
   git clone git@github.com:marc-ferre/nanomito.git
   cd nanomito
   ```

2. **Configure the environment:**

   Edit `nanomito.config` to match your HPC environment:

   ```bash
   # Open the configuration file
   nano nanomito.config

   # Update all paths:
   # - DORADO_BIN, BALDUR_BIN, ONT_DEMULT_BIN
   # - All conda environment paths (ANNOTMT_ENV, BCHG_ENV, etc.)
   # - Workflow script paths (WF_BCHG, WF_DEMULTMT, etc.)
   # - Reference genome paths (REF_MT, REF_WHOLE, etc.)
   # - Annotation database paths (ANN_GNOMAD, ANN_MITOMAP_*, etc.)
   # - MAIL_USER with your email address
   ```

3. **Make scripts executable:**

   ```bash
   chmod +x *.sh
   ```

## Usage

### Prerequisites: Data Preprocessing

Before running the main workflows, you need to prepare the chrM-specific Pod5 files and create the read ID mapping:

```bash
# On Windows/WSL (where Dorado BAM files are located)
cd /mnt/c/data/your_run_directory
/path/to/nanomito/preprocessing/wf-getmt.sh .

# This creates:
# - pod5_chrM/<RUN_ID>.chrM.pod5 (filtered Pod5 with chrM reads)
# - pod5_chrM/<RUN_ID>.pid_dict.tsv (read-to-parent ID mapping)
# - pod5_chrM/<RUN_ID>.chrM_pids.txt (list of parent read IDs)
```

### Basic Workflow Execution

```bash
# Navigate to your run directory
cd /scratch/username/workbench/run_directory

# Submit the complete workflow (basecalling + all analysis)
/path/to/nanomito/submit_nanomito.sh .

# Only basecalling and demultiplexing
/path/to/nanomito/submit_nanomito.sh --bchg-only .

# Skip basecalling, run all analysis workflows
/path/to/nanomito/submit_nanomito.sh --skip-bchg .
```

### Advanced Workflow Filtering

Selective workflow execution is useful for re-running specific parts of the analysis:

```bash
# Re-run only demultmt workflows (e.g., after changing read selection strategy)
/path/to/nanomito/submit_nanomito.sh --skip-bchg --demultmt-only .

# Re-run only modmito workflows (e.g., demultmt already completed)
/path/to/nanomito/submit_nanomito.sh --skip-bchg --modmito-only .

# Run complete pipeline but skip modmito (e.g., only need demultiplexed reads)
/path/to/nanomito/submit_nanomito.sh --skip-modmito .

# Run complete pipeline but skip demultmt (e.g., only need modification analysis)
/path/to/nanomito/submit_nanomito.sh --skip-demultmt .
```

**Note:** The `--demultmt-only` and `--modmito-only` options require `--skip-bchg` because they assume samples already exist in `fastq_pass/`.

### Manual Step Execution

For debugging or custom workflows, you can submit individual jobs manually:

```bash
# Submit only basecalling & demux
sbatch --chdir=/path/to/run /path/to/nanomito/wf-bchg.sh

# Submit the orchestrator to discover and process all samples
sbatch --chdir=/path/to/run /path/to/nanomito/wf-subwf.sh

# Process a specific sample directly (not recommended, use submit_nanomito.sh instead)
sbatch --chdir=/path/to/run /path/to/nanomito/wf-demultmt.sh SAMPLE_ID
sbatch --chdir=/path/to/run /path/to/nanomito/wf-modmito.sh SAMPLE_ID
```

### Monitoring Jobs

```bash
# Check job status
squeue -u $USER

# Check specific jobs
squeue -j job_id_1,job_id_2

# View logs
tail -f processing/slurm-*.out processing/*/slurm-*.out
```

## Configuration

### Global Configuration File

All paths and environment variables are centralized in the `nanomito.config` file located at the root of the repository. This file must be edited once to match your environment before running any workflows.

**Configuration file structure:**

```bash
# Binaries
DORADO_BIN='/path/to/dorado'
BALDUR_BIN='/path/to/baldur'
ONT_DEMULT_BIN='/path/to/ont_demult'

# Conda environments
ANNOTMT_ENV='/path/to/env_annotmt'
BALDUR_ENV='/path/to/env_baldur'
BCHG_ENV='/path/to/env_bchg'
GETMT_ENV='/path/to/env_getmt'
MODMITO_ENV='/path/to/env_modmito'
ONT_DEMULT_ENV='/path/to/env_ont_demult'
POD5_ENV='/path/to/env_pod5'

# Python scripts
CHRMPIDS_SCRIPT='/path/to/get_chrMpid.py'
CREATE_PID_DICT_SCRIPT='/path/to/create_pid_dict.py'

# Workflow scripts
WF_BCHG='/path/to/wf-bchg.sh'
WF_SUBWF='/path/to/wf-subwf.sh'
WF_DEMULTMT='/path/to/wf-demultmt.sh'
WF_MODMITO='/path/to/wf-modmito.sh'

# Reference genomes
REF_MT='/path/to/chrM.fa'
REF_MT_DIR='/path/to/reference'
REF_WHOLE='/path/to/Homo_sapiens-hg38-GRCh38.p14.mmi'
SELECTED_REF='/path/to/chrM-mt_3kb-a0.fa'
CUT_FILE='/path/to/cut.txt'

# Annotation databases
ANN_GNOMAD='/path/to/gnomad.genomes.v3.1.sites.chrM.vcf'
ANN_MITOMAP_DISEASE='/path/to/disease-nosp.vcf'
ANN_MITOMAP_POLYMORPHISMS='/path/to/polymorphisms.vcf'

# SLURM mail configuration
MAIL_USER='your.email@domain.com'
```

**How to customize:**

1. Open `nanomito.config` in a text editor
2. Update all paths to match your HPC environment
3. Update the `MAIL_USER` variable with your email address
4. Save the file

All workflow scripts automatically source this configuration file, so changes apply immediately to all workflows without editing individual scripts.

### Sample Sheet Format

Required CSV file with ONT sample information:

```csv
protocol_run_id,position_id,flow_cell_id,sample_id,experiment_id,flow_cell_product_code,kit,barcode,alias,type
...
```

### Key Parameters

**wf-bchg.sh:**

- `MODEL`: Basecalling model (default: `sup`)
- `KIT`: Barcoding kit (default: `SQK-NBD114-24`)

**wf-demultmt.sh:**

- `SELECT`: Read selection strategy (`both`, `start`, `either`, `xor`)

**wf-modmito.sh:**

- `MODEL_COMPLEX`: Modification model (default: `sup,5mC_5hmC,6mA`)

## Output Files

### Per Sample

- **FASTQ files:** `fastq_pass/barcode_XX/*.fastq.gz`
- **Demultiplexed reads:** `processing/sample/select-both/*.fastq.gz`
- **BAM alignments:** `processing/sample/*.sorted.bam`
- **BedMethyl:** `processing/sample/*.combine.bed`
- **Logs:** `processing/sample/slurm-*.out` and `processing/sample/slurm-*.err`

### Summary

- **Workflow summary:** `processing/workflows_summary.<RUN_ID>.tsv`
- **HTML report (fallback if no mailer):** `processing/report.<RUN_ID>.html`
- **Finalize job log:** `processing/slurm-<RUN_ID>.final.out`

## Troubleshooting

### Common Issues

1. **"Workflow script not found"**

   - Check paths in `submit_nanomito.sh`
   - Ensure scripts are executable

1. **"Failed to load Conda"**

   - Scripts automatically handle conda loading failures
   - Check `/local/env/envconda.sh` exists

1. **"Failed to retrieve read IDs from BAM files"**

   - Ensure preprocessing was run first: `wf-getmt.sh` must create `pid_dict.tsv`
   - Check that `pod5_chrM/<RUN_ID>.pid_dict.tsv` exists
   - Verify the dictionary file is not empty

1. **"NO DATA" warnings in logs/email**

   - This is **not an error** - some samples may have no reads matching both patient and reference mitochondria
   - The workflow completes successfully and creates a `NO_DATA.marker` file
   - These samples are automatically skipped in downstream analysis (modmito)
   - The final email report will show these samples with a warning in the PRE-FLIGHT CHECK section
   - To reprocess only specific samples (e.g., failed or NO DATA samples), use `--only-samples`:

     ```bash
     ./submit_nanomito.sh --skip-bchg --only-samples SAMPLE1,SAMPLE2 /path/to/run/
     ```

1. **GPU not available**

   - Ensure `--partition=gpu` is set
   - Check GPU availability: `sinfo -p gpu`

1. **Out of memory**

   - Adjust `--mem` in SBATCH headers
   - Monitor with `sstat -j $SLURM_JOB_ID`

### Viewing Error Logs

```bash
# Check .err files for errors
cat processing/slurm-*.err

# Check .out files for detailed output
less processing/sample/slurm-sample.demultmt.out
```

### Quick Check (pre-flight validator)

Before sending the final HTML email, you can quickly validate that key artifacts are present for a run directory:

```bash
# From the repository root
tools/check_run_ready.sh /path/to/run

# Strict mode (exit 1 if required artifacts are missing)
tools/check_run_ready.sh /path/to/run --strict
```

What it checks:

- processing/ directory exists
- Summary files in processing/: workflows_summary.RUN_ID.tsv, demult_summary.RUN_ID.tsv, haplocheck_summary.RUN_ID.tsv (warn if missing)
- Per-sample outputs in processing/SAMPLE/:
  - SAMPLE.chrM.sup,5mC_5hmC,6mA.sorted.bam (required)
  - SAMPLE.ann.vcf (warn) and SAMPLE.ann.tsv (warn)
  - varcall/SAMPLE.baldur_del.txt (warn)
- Archiving summary: archiving_summary.RUN_ID.tsv (warn)

It prints a compact PASS/WARN/FAIL summary and returns non‑zero in strict mode if a required artifact is missing.

## Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on HPC cluster
5. Submit a pull request

### Coding Standards

- All scripts use `set -euo pipefail` for strict error handling
- Consistent logging functions: `log_info`, `log_success`, `log_error`, `log_warning`
- Comprehensive inline documentation
- English comments and documentation

## License

This project is licensed under the **CeCILL License v2.1** - see the [LICENSE](LICENSE) file for details.

The CeCILL license is a Free Software license agreement adapted to French law, compatible with the GNU GPL, and specifically designed for CNRS, INSERM, and INRIA projects.

**Key points:**

- ✅ Free to use, modify, and distribute
- ✅ Strong copyleft: derivative works must also be open-source
- ✅ Compliant with French law and European regulations
- ✅ Guarantees that improvements remain in the public domain

More information: <http://www.cecill.info>

## Author

**Marc FERRE**  
Email: <marc.ferre@univ-angers.fr>  
Institution: CNRS UMR6015 / INSERM UMR1083

## Citation

If you use Nanomito in your research, please cite:

<!-- markdownlint-disable MD034 -->
```bibtex
@software{nanomito2026,
  author = {Ferré, Marc},
  title = {Nanomito: An Amplification-Free Long-Read Workflow for
           Single-Molecule mtDNA Variant Calling and Deletion
           Quantification in Clinical Diagnostics},
  year = {2026},
  url = {https://github.com/marc-ferre/nanomito}
}
```
<!-- markdownlint-enable MD034 -->

## Acknowledgments

The project underlying this work was selected for the Oxford Nanopore Technologies MinION Access Programme in 2014, which provided early access to Oxford Nanopore technology.

We acknowledge the [GenOuest bioinformatics core facility](https://www.genouest.org) for providing the computing infrastructure.

## Version History

- **v2.5.0** (2026-03-23) - Public release hardening
  - **License headers:** SPDX-License-Identifier + Author metadata added to all scripts (32/32 compliant)
  - **Anonymization:** All personal HPC paths, email addresses, and SSH credentials replaced with generic placeholders in config templates
  - **Git hygiene:** Runtime configs (`nanomito.config`, `preprocessing.config`, `config/`) confirmed excluded from tracking; generated test artifacts (`sample_ANON*`, `tmp_out/`, `tmp_out2/`) purged and gitignored
  - **Template alignment:** `preprocessing/preprocessing.config.template` aligned to match `preprocessing.config` (12/12 variables, inline comments, section naming)
  - **Citation:** Updated title and year to match associated manuscript
  - **Acknowledgments:** Added ONT MinION Access Programme and GenOuest acknowledgments

- **v2.2.4** (2025-12-31) - Preprocessing improvements and report generation
  - **Preprocessing enhancements:** HTML report generator with comprehensive metrics
  - **Progress visualization:** Progress bar for chrM Pod5 percentage tracking
  - **Metrics expansion:** Percentage of total Pod5 files and Total Pod5 Files size metrics
  - **Automatic cleanup:** Robust Dorado temp directory cleanup from both run and working directories
  - **File management:** Dorado log copying to pod5_chrM directory with proper naming
  - **Report archiving:** SHA256 checksum verification for archived reports
  - **Encoding fixes:** Emoji replaced with ASCII text for proper string handling
  - **Error handling:** Improved PowerShell temp file capture for Dorado execution
  - **Configuration support:** NANOMITO_DIR support in submit_nanomito.sh

- **v2.1.0** (2024-12-24) - Interactive per-sample HTML reports
  - **Per-sample HTML reports** - Individual interactive reports for each sample
  - **Interactive variants table** - PASS filter toggle button
  - **Disease coloring** - Pathogenic, likely-pathogenic, benign variants highlighted
  - **Comprehensive metrics** - Alignment, haplogroup, variants, and deletions counts
  - **Responsive design** - Mobile-optimized layout with adaptive tables
  - **Column width limiting** - Max 200px with ellipsis and hover expansion
  - **Footer** - Creator name and email information
  - **--reports-only option** - Regenerate reports without sending email
  
  **Report Features:**
  - Run metrics header (total/passed reads and bases with thousand separators)
  - Stat cards grid: Alignment (chrM reads, Matching both), Haplogroup (Status, Major), Variants (Total, PASS, Highlighted), Deletions (Total, Highlighted)
  - Horizontal haplogroup table with all haplocheck columns
  - Variants table with interactive PASS filter and disease coloring
  - Deletions table with deduplicated mirrored +/- pairs
  - Output files section with file sizes and validation badges
  - Logs section displaying errors and warnings from processing
  - Saved as `processing/<SAMPLE>/report-<SAMPLE>.html`
  
  **Bug Fixes:**
  - Fixed deletions count to match table display (deduplicates mirrored pairs)
  - Fixed PASS filter applying to all tables (now only affects variants table)
  - Fixed optional parameter handling in tsv_to_html_table function

- **v2.0.0** (2025-11-04) - Major workflow improvements and HTML email reports
  - **Integrated archiving workflow** with automatic dependency management
  - Beautiful responsive HTML email reports optimized for mobile viewing
  - **BREAKING:** Archiving enabled by default (use `--skip-archiving` to disable)
  - **BREAKING:** Email format changed to HTML with responsive design
  
  **Workflow Enhancements:**
  - Fixed critical job dependency bug (archiving/finalize now wait for all sample jobs)
  - Added `--skip-archiving` and `--archiving-only` options
  - `wf-subwf.sh` now handles archiving/finalize submission with proper dependencies
  - Archiving summary with human-readable sizes and duration metrics
  
  **Email Report Features:**
  - Responsive HTML design with embedded CSS
  - Color-coded status indicators (success/warning/error)
  - Mobile-optimized layout for iPhone and Android
  - Per-sample results with alignment stats, haplogroups, variant counts, file sizes
  - Deletions table from Baldur analysis with columns: Start / Stop / Strand / Length / Type / Count (sorted by Start,Stop; mirrored +/- intervals merged as ± with summed Count)
  - Archiving summary section with destination, size, and duration
  - Fixed total runtime calculation (was showing 00:00:00)
  - English number formatting (331,496 and 3.7G instead of French format)
  - Uniform time formatting (HH:MM:SS with two digits)
  
  **Configuration:**
  - Removed `END` from `MAIL_TYPE` variables to prevent success email spam
  - SLURM emails now sent only on failures
  - Success notifications handled exclusively by `wf-finalize.sh` HTML email
  
  **Bug Fixes:**
  - Fixed job dependency chain: sample jobs → archiving → finalize
  - Fixed total runtime calculation (subshell variable scope issue)
  - Fixed TSV parsing for empty fields (sample_id display)
  - Fixed decimal format for archive sizes (3.7G instead of 3,7G)
  - Removed double slashes in error log file paths
  
  **Documentation:**
  - Updated README with archiving features and workflow diagram
  - Updated TODO marking completed tasks
  - All commit messages in English

- **v1.1.1** (2025-11-04) - Email notification optimization
  - Disabled SLURM success emails (`END` removed from `--mail-type`)
  - SLURM emails now sent only on failures (FAIL, INVALID_DEPEND, REQUEUE, etc.)
  - Success notification handled exclusively by `wf-finalize.sh` final email
  - Significantly reduces email noise while maintaining critical failure alerts

- **v1.1.0** (2025-11-04) - Configuration management and workflow enhancements
  - Added global configuration file `nanomito.config` for centralized settings
  - New `--include-unclassified` option to process unclassified reads (skipped by default)
  - Optimized SLURM resource requests for faster job scheduling
  - Standardized per-sample logging: split `.out` and `.err` files for demultmt/modmito workflows
  - Single final notification email with comprehensive log tails and run summary
  - Improved documentation with ASCII workflow diagram
  - Enhanced error handling and path resolution in SLURM contexts

- **v1.0.1** (2025-11-04) - Final notification email and resource tuning
  - Added `wf-finalize.sh` and automatic final job submission from `wf-subwf.sh`
  - Sends a single email with run summary and log tails when all jobs finish
  - Updated recommended SLURM resources (GPU jobs: 6 CPUs/32GB; demultmt: 8 CPUs/100GB)

- **v1.0.0** (2025-11-03) - Production release with architecture refinement
  - **BREAKING:** Restored two-step workflow architecture with `wf-subwf.sh`
  - Added workflow filtering options: `--demultmt-only`, `--skip-demultmt`, `--modmito-only`, `--skip-modmito`
  - Fixed dynamic sample discovery: `wf-subwf.sh` discovers samples after basecalling completes
  - Improved option validation and help messages
  - Enhanced logging to show active workflow modes
  - Repository structure: maintained `nanomito/` directory name
  - All Dorado 1.2.0 compatibility fixes validated
  - Tested end-to-end on production data (4 samples, all haplogroups detected)
  
- **v25.10.27** - Major architecture simplification and cleanup
  - Integrated `wf-subwf.sh` functionality directly into `submit_nanomito.sh` (reverted in v1.0.0)
  - Added `--skip-bchg` and `--bchg-only` options for flexible workflow execution
  - Removed Archive/ directory (all history available via Git)
  - Renamed repository directory from `workflows/` to `nanomito/`
  - Added preprocessing workflow with PID dictionary creation
  - New `preprocessing/wf-getmt.sh` for chrM read extraction
  - New `preprocessing/create_pid_dict.py` for read-to-parent ID mapping
  - Updated `get_chrMpid.py` to use dictionary files
  - Fixed SIGPIPE errors in `wf-demultmt.sh`
  - Improved error handling and logging
  
- **v25.10.26** - Major improvements: robust error handling, comprehensive documentation

- **v25.05.18** - Initial release

## Accessing Historical Versions

All previous versions and architectural variations are accessible through Git history:

```bash
# View file history
git log -- path/to/file.sh

# View a specific old version
git show <commit-hash>:path/to/file.sh

# Restore an old version if needed
git checkout <commit-hash> -- path/to/file.sh
```

---

**Status:** Production-ready | **Platform:** SLURM/HPC | **Technology:** Oxford Nanopore
