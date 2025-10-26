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
│              Main workflow submission orchestrator               │
└──────────────────┬──────────────────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        ▼                     ▼
┌───────────────┐     ┌───────────────┐
│  wf-bchg.sh   │     │ wf-subwf.sh   │
│  Basecalling  │────▶│  Per-sample   │
│  & Demux      │     │  orchestrator │
└───────────────┘     └───────┬───────┘
                              │
                   ┌──────────┴──────────┐
                   ▼                     ▼
           ┌──────────────┐      ┌──────────────┐
           │wf-demultmt.sh│      │wf-modmito.sh │
           │ MT reads     │─────▶│ Modification │
           │ demultiplex  │      │ analysis     │
           └──────────────┘      └──────────────┘
```

## Workflows Description

### 1. **submit_nanomito.sh**

Main entry point for workflow submission. Orchestrates the entire pipeline execution.

**Usage:**

```bash
./submit_nanomito.sh /path/to/run/directory
```

### 2. **wf-bchg.sh** (Basecalling & Demultiplexing)

- GPU-accelerated basecalling using Dorado
- Automatic sample demultiplexing by barcodes
- FASTQ compression and organization
- **Resources:** 1 GPU, 12 CPUs, 50GB RAM

### 3. **wf-subwf.sh** (Sub-workflow Orchestrator)

- Automatically detects samples in `fastq_pass/`
- Submits demultmt and modmito jobs for each sample
- Manages job dependencies

### 4. **wf-demultmt.sh** (Mitochondrial Reads Demultiplexing)

- Maps reads to reference genome
- Demultiplexes mitochondrial reads by patient
- Read selection strategies (both/start/either/xor)
- **Resources:** 12 CPUs, 150GB RAM

### 5. **wf-modmito.sh** (Modification Analysis)

- Duplex basecalling with modification calling (5mC, 5hmC, 6mA)
- BAM alignment and sorting
- BedMethyl output generation
- **Resources:** 1 GPU, 12 CPUs, 50GB RAM

### 6. **archiving.sh**

Automated run archiving to project storage.

## Directory Structure

```text
run_directory/
├── pod5_chrM/                    # POD5 files (chrM reads only)
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
- **Conda** environment with:
  - minimap2
  - samtools
  - modkit
  - ont_demult
- **GNU Parallel** (optional, for faster compression)

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

- **v25.10.26** - Major improvements: robust error handling, comprehensive documentation
- **v25.05.18** - Initial release

---

**Status:** Production-ready | **Platform:** SLURM/HPC | **Technology:** Oxford Nanopore
