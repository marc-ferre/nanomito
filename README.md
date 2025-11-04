# Nanomito

Comprehensive SLURM workflows for full-length single-molecule sequencing of mitochondrial DNA using Oxford Nanopore Technology.

## Overview

Nanomito is a collection of production-ready bash scripts designed for high-throughput processing of Oxford Nanopore sequencing data, specifically optimized for mitochondrial DNA analysis. The workflows are designed to run on HPC clusters using SLURM workload manager.

### Key Features

- 🧬 **Full mitochondrial genome sequencing** - Complete workflow from basecalling to modification analysis
- 🚀 **GPU-accelerated basecalling** - Leverages Dorado for high-accuracy basecalling with modification detection
- 🔀 **Sample demultiplexing** - Automated barcode demultiplexing and patient-level separation
- 🔬 **Modification detection** - 5mC, 5hmC, and 6mA base modification calling
- 📊 **SLURM integration** - Optimized for HPC environments with automatic job dependency management
- 📧 **Single final notification email** - One email when all jobs finish, with a summary and log tails
- ✅ **Robust error handling** - Comprehensive logging and error recovery mechanisms

## Workflow Architecture

Rendered diagram (Mermaid):

```mermaid
flowchart TD
   A[submit_nanomito.sh<br/>Main orchestrator] -->|submit| B[wf-bchg.sh<br/>GPU basecalling + demux]
   A -->|submit| C[wf-subwf.sh<br/>sample discovery + submissions]
   B -->|afterok| C

   C --> D{for each SAMPLE}

   subgraph "Per-sample"
      E[wf-demultmt.sh<br/>(per sample)] -->|afterok| F[wf-modmito.sh<br/>(per sample)]
   end

   D --> E
   F -->|afterok: all per-sample jobs| G[wf-finalize.sh<br/>single email]
```

Static SVG (auto-généré par CI): `diagrams/workflow.svg`

**Two-step submission architecture:**

1. `submit_nanomito.sh` submits `wf-bchg.sh` and `wf-subwf.sh`
2. `wf-subwf.sh` waits for basecalling completion, discovers samples, then submits analysis jobs
3. `wf-subwf.sh` also submits a final job (`wf-finalize.sh`) that sends a single notification email when all jobs finish

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
- `--include-unclassified` - Include 'unclassified' folder in sample processing (skipped by default)
- `--help, -h` - Display help message

**Features:**

- Two-step submission architecture for dynamic sample discovery
- Submits `wf-subwf.sh` which discovers samples after basecalling
- Automatically skips 'unclassified' folder (use `--include-unclassified` to process it)
- Manages job dependencies automatically
- Supports selective workflow execution with filtering options
- Validation of option compatibility

### 2. **wf-subwf.sh** (Workflow Orchestrator)

Intermediate orchestrator that dynamically discovers samples and submits analysis jobs.

- Waits for basecalling completion via SLURM dependencies
- Discovers all samples in `fastq_pass/` directory
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

### 6. **wf-finalize.sh** (Single final notification)

- Submitted automatically by `wf-subwf.sh` after all per-sample jobs are queued
- Waits for successful completion of all jobs (SLURM `afterok` dependency)
- Sends a single email to `MAIL_USER` with:
   - Run metadata (Run ID, date, path)
   - The `processing/workflows_summary.<RUN_ID>.tsv` content if present
   - Tails of main logs: `slurm-<RUN_ID>.bchg.out` and `slurm-<RUN_ID>.subwf.out`
   - Tails of per-sample logs (demultmt/modmito), limited for brevity
- If no mailer is available (`mail`, `mailx`, or `sendmail`), saves the email body to `processing/email-<RUN_ID>.txt`

### 7. **archiving.sh**

Automated run archiving to project storage.

## Preprocessing Workflows

### **wf-getmt.sh** (Extract chrM reads from raw data)

Located in `preprocessing/`, this script is used to prepare data before the main workflow:

- Analyzes Dorado BAM files to identify reads aligned to chrM
- Creates a read_id→parent_id dictionary (`pid_dict.tsv`) from BAM tags
- Filters Pod5 files to extract only chrM-aligned reads
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
│   ├── email-<RUN_ID>.txt       # Email body (if mailer unavailable)
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

### Installation on Genouest HPC

1. **Clone the repository:**

   ```bash
   # Generate SSH key if not already done
   ssh-keygen -t ed25519 -C "your.email@domain.com"
   cat ~/.ssh/id_ed25519.pub  # Add this to GitHub Settings > SSH keys

   # Clone the repository
   cd /home/genouest/.../your_username/
   git clone git@github.com:marc-ferre/nanomito.git
   cd nanomito
   ```

1. **Configure the environment:**

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

1. **Make scripts executable:**

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
- **Final email body (fallback if no mailer):** `processing/email-<RUN_ID>.txt`
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

```bibtex
@software{nanomito2025,
  author = {Ferré, Marc},
  title = {Nanomito: Workflows for mitochondrial DNA sequencing},
  year = {2025},
  url = {https://github.com/marc-ferre/nanomito}
}
```

## Acknowledgments

- **Genouest** bioinformatics platform for HPC resources
- **Oxford Nanopore Technologies** for sequencing technology
- **Dorado** team for basecalling software

## Version History

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

**Notable commits:**

- **v1.0.0** (current): Two-step architecture with `wf-subwf.sh` for dynamic sample discovery
- **8f50c84**: Refactored to restore `wf-subwf.sh` workflow
- **6fe53ae**: Single-step architecture (samples discovered in `submit_nanomito.sh`)
- **3983d5a**: Original two-step architecture before temporary simplification

---

**Status:** Production-ready | **Platform:** SLURM/HPC | **Technology:** Oxford Nanopore
