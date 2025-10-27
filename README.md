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
- ✅ **Robust error handling** - Comprehensive logging and error recovery mechanisms

## Workflow Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                     submit_nanomito.sh                          │
│         Main workflow submission orchestrator with options       │
│         --bchg-only: Only basecalling/demux                     │
│         --skip-bchg: Skip basecalling, only analysis            │
└──────────────────┬──────────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┬──────────────────────────┐
        ▼                     ▼                          ▼
┌───────────────┐     ┌──────────────┐         ┌──────────────┐
│  wf-bchg.sh   │     │wf-demultmt.sh│         │wf-modmito.sh │
│  Basecalling  │────▶│ MT reads     │────────▶│ Modification │
│  & Demux      │     │ demultiplex  │         │ analysis     │
└───────────────┘     │ (per sample) │         │ (per sample) │
                      └──────────────┘         └──────────────┘
```

## Workflows Description

### 1. **submit_nanomito.sh**

Main entry point for workflow submission. Orchestrates the entire pipeline execution and directly submits all jobs with proper dependencies.

**Usage:**

```bash
# Submit complete pipeline (basecalling + analysis)
./submit_nanomito.sh /path/to/run/directory

# Only basecalling and demultiplexing
./submit_nanomito.sh --bchg-only /path/to/run/directory

# Skip basecalling, only submit analysis workflows (for pre-existing FASTQ files)
./submit_nanomito.sh --skip-bchg /path/to/run/directory

# Display help
./submit_nanomito.sh --help
```

**Features:**

- Discovers samples in `fastq_pass/` directory
- Submits demultmt and modmito jobs for each sample
- Manages job dependencies automatically
- Supports selective workflow execution with options

### 2. **wf-bchg.sh** (Basecalling & Demultiplexing)

- GPU-accelerated basecalling using Dorado
- Automatic sample demultiplexing by barcodes
- Sample sheet alias mapping for directory organization
- FASTQ compression and organization
- **Resources:** 1 GPU, 12 CPUs, 50GB RAM

### 3. **wf-demultmt.sh** (Mitochondrial Reads Demultiplexing)

- Maps reads to reference genome
- Demultiplexes mitochondrial reads by patient
- Read selection strategies (both/start/either/xor)
- Creates read_id→parent_id dictionary for Pod5 filtering
- **Resources:** 12 CPUs, 150GB RAM

**Note:** This workflow expects a `pid_dict.tsv` file created during preprocessing (see `preprocessing/wf-getmt.sh`) that maps read IDs to their parent IDs for proper Pod5 file filtering.

### 4. **wf-modmito.sh** (Modification Analysis)

- Duplex basecalling with modification calling (5mC, 5hmC, 6mA)
- BAM alignment and sorting
- BedMethyl output generation
- **Resources:** 1 GPU, 12 CPUs, 50GB RAM

### 5. **archiving.sh**

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
│   │   ├── slurm-sample_1.demultmt.log
│   │   ├── slurm-sample_1.modmito.log
│   │   └── select-both/         # Demultiplexed patient files
│   └── workflows_summary.tsv    # Runtime summary
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
git clone git@github.com:marc-ferre/nanomito.git workflows
cd workflows
```

1. **Update workflow paths:**

Edit the workflow files to match your environment:

- `WF_BCHG`, `WF_SUBWF`, etc. in `submit_nanomito.sh`
- `DORADO_BIN` path in `wf-bchg.sh` and `wf-modmito.sh`
- Conda environment paths

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
/path/to/workflows/preprocessing/wf-getmt.sh .

# This creates:
# - pod5_chrM/<RUN_ID>.chrM.pod5 (filtered Pod5 with chrM reads)
# - pod5_chrM/<RUN_ID>.pid_dict.tsv (read-to-parent ID mapping)
```

### Basic Workflow Execution

```bash
# Navigate to your run directory
cd /scratch/username/workbench/run_directory

# Submit the complete workflow
/path/to/workflows/submit_nanomito.sh .
```

### Manual Step Execution

```bash
# Submit only basecalling & demux
sbatch --chdir=/path/to/run /path/to/workflows/wf-bchg.sh

# Submit sample processing (after basecalling)
sbatch --chdir=/path/to/run /path/to/workflows/wf-subwf.sh

# Process a specific sample
sbatch --chdir=/path/to/run /path/to/workflows/wf-demultmt.sh barcode09
sbatch --chdir=/path/to/run /path/to/workflows/wf-modmito.sh barcode09
```

### Monitoring Jobs

```bash
# Check job status
squeue -u $USER

# Check specific jobs
squeue -j job_id_1,job_id_2

# View logs
tail -f processing/slurm-*.log
```

## Configuration

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
- **Logs:** `processing/sample/slurm-*.log`

### Summary

- **Workflow summary:** `processing/workflows_summary.tsv`

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

# Check .log files for detailed output
less processing/sample/slurm-sample.workflow.log
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

- **v25.10.27** - Added preprocessing workflow with PID dictionary creation
  - New `preprocessing/wf-getmt.sh` for chrM read extraction
  - New `preprocessing/create_pid_dict.py` for read-to-parent ID mapping
  - Updated `get_chrMpid.py` to use dictionary files
  - Fixed SIGPIPE errors in `wf-demultmt.sh`
  - Improved error handling and logging
- **v25.10.26** - Major improvements: robust error handling, comprehensive documentation
- **v25.05.18** - Initial release

---

**Status:** Production-ready | **Platform:** SLURM/HPC | **Technology:** Oxford Nanopore
