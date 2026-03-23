# Preprocessing Workflows

Preprocessing workflows for Nanopore sequencing data before running the main Nanomito analysis pipeline.

## Overview

The preprocessing directory contains workflows for preparing Nanopore sequencing data on Windows before uploading to an HPC cluster for analysis. The workflow consists of:

1. **Basecalling** (Windows) - Convert raw POD5 files to BAM using Dorado
2. **chrM extraction** (WSL) - Filter reads aligned to mitochondrial chromosome
3. **Upload** (WSL) - Transfer data to HPC cluster

```text
┌─────────────────────────────────────────────────────────────┐
│                   Windows Workstation                       │
│                                                             │
│  ┌──────────────┐     ┌──────────────┐     ┌─────────────┐  │
│  │wf-prebchg.ps1│────▶│ wf-getmt.sh  │────▶│wf-uplgo.sh  │  │
│  │              │     │              │     │             │  │
│  │  Dorado      │     │ Extract chrM │     │ Upload to   │  │
│  │  Basecalling │     │ reads        │     │ HPC         │  │
│  └──────────────┘     └──────────────┘     └─────────────┘  │
│        │                     │                    │         │
│        ▼                     ▼                    ▼         │
│    bam/*.bam         pod5_chrM/*.pod5      rsync to HPC     │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
                        ┌───────────────┐
                        │  HPC Cluster  │
                        │  /scratch/... │
                        └───────────────┘
```

**Orchestration:**

- **Manual:** Run each script individually
- **Automated:** Use `submit_preprocessing.ps1` to run the complete pipeline

## Public Release Hygiene

Before publishing this repository:

- Keep personal paths, usernames, and email values in local config files only.
- Commit templates (`preprocessing.config.template`, `preprocessing.ps1` defaults/examples) instead of environment-specific secrets/paths.
- Remove generated logs and test outputs containing absolute local paths.
- Recheck script headers for SPDX + Author consistency.

## Prerequisites

### Windows Requirements

- **PowerShell 5.1+** or **PowerShell Core 7+**
- **Dorado** - GPU basecaller (version 1.1.1+)
- **WSL (Windows Subsystem for Linux)** - Ubuntu recommended
- **Python 3.8+** with `pysam` library

### WSL Requirements

- **Conda/Miniconda** - For environment management
- **Python 3.9+** - In conda environment
- **pysam** - Python library for BAM file manipulation
- **pod5** - Python package for Pod5 file filtering
- **samtools** - BAM file processing tools
- **rsync** - File synchronization
- **SSH key** - For passwordless authentication to HPC cluster

**Conda environment:** All Python tools should be installed in a dedicated conda environment named `nanomito` (see Installation section).

## Quick Start

### 1. Configure Paths

Edit configuration files to match your environment:

```powershell
# Edit Windows configuration
notepad preprocessing\preprocessing.ps1

# Edit Linux/WSL configuration (in WSL)
nano preprocessing/preprocessing.config
```

### 2. Run Complete Pipeline

```powershell
# From Windows PowerShell, in the preprocessing directory
cd C:\Users\YourName\nanomito\preprocessing

# Auto-detect latest run and process everything
.\submit_preprocessing.ps1

# Or specify a run directory
.\submit_preprocessing.ps1 -RunDirectory "C:\data\run_dir"

# Dry run (preview without execution)
.\submit_preprocessing.ps1 -DryRun
```

### 3. Run Individual Steps

```powershell
# Step 1: Basecalling only
.\wf-prebchg.ps1 -RunDirectory "C:\data\run_dir"

# Step 2: Extract chrM reads (in WSL)
wsl ./preprocessing/wf-getmt.sh /mnt/c/data/run_dir

# Step 3: Upload to HPC (in WSL)
wsl ./preprocessing/wf-uplgo.sh /mnt/c/data/run_dir
```

## Detailed Documentation

### Scripts

#### 1. **wf-prebchg.ps1** (Windows/PowerShell)

**Purpose:** GPU-accelerated basecalling using Dorado with alignment to reference genome.

**Features:**

- Automatic detection of latest run directory
- Basecalling with sample demultiplexing
- Alignment to human reference genome (hg38)
- Robust error handling and logging

**Usage:**

```powershell
# Auto-detect latest run
.\wf-prebchg.ps1

# Specific run directory
.\wf-prebchg.ps1 -RunDirectory "C:\data\run_dir"

# Custom model and kit
.\wf-prebchg.ps1 -RunDirectory "C:\data\my_run" -Model "sup" -Kit "SQK-NBD114-24"

# Help
.\wf-prebchg.ps1 -Help
```

**Parameters:**

- `-RunDirectory` - Path to run directory (auto-detects latest if omitted)
- `-Model` - Basecalling model: `fast`, `hac`, `sup` (default: `hac`)
- `-Kit` - Sequencing kit (default: `SQK-NBD114-24`)
- `-DoradoBasePath` - Dorado installation path
- `-DoradoExecutable` - Dorado executable relative path
- `-ReferencePath` - Reference genome (.mmi file)
- `-LogPath` - Log file path

**Outputs:**

- `bam/` - BAM files with alignment tags
- `bam/*.bam` - Per-barcode BAM files
- `bam/dorado_run.log` - Execution log

**Time:** ~2-4 hours for typical run (depends on GPU and data size)

---

#### 2. **wf-getmt.sh** (Linux/WSL/Bash)

**Purpose:** Extract reads aligned to mitochondrial chromosome (chrM) from Dorado BAM files.

**Features:**

- Extracts chrM read IDs from BAM files
- Creates read_id → parent_id dictionary (required for downstream analysis)
- Filters Pod5 files to keep only chrM reads
- Automatic run detection

**Usage:**

```bash
# In WSL
cd /mnt/c/Users/YourName/nanomito/preprocessing

# Auto-detect latest run
./wf-getmt.sh

# Specific run directory
./wf-getmt.sh /mnt/c/data/run_dir

# Custom log file
./wf-getmt.sh -l /tmp/custom.log /mnt/c/data/my_run
```

**Parameters:**

- `[RUN_DIRECTORY]` - Path to run directory (auto-detects latest if omitted)
- `-l|--log LOGFILE` - Custom log file path

**Outputs:**

- `pod5_chrM/<RUN_ID>.chrM.pod5` - Filtered Pod5 file (chrM reads only)
- `pod5_chrM/<RUN_ID>.pid_dict.tsv` - Read-to-parent ID mapping
- `pod5_chrM/<RUN_ID>.chrM_pids.txt` - List of parent read IDs
- `pod5_chrM/<RUN_ID>.wf-getmt.log` - Execution log

**Important:** The `pid_dict.tsv` file is **required** for the main Nanomito workflow (`wf-demultmt.sh`) to properly map reads.

**Time:** ~10-30 minutes depending on BAM file size

---

#### 3. **wf-uplgo.sh** (Linux/WSL/Bash)

**Purpose:** Upload run data to HPC cluster using rsync.

**Features:**

- Excludes large data files (pod5, bam, fastq) - only syncs metadata
- SSH key-based authentication
- Dry-run mode for preview
- Automatic run detection
- Progress display

**Usage:**

```bash
# In WSL
cd /mnt/c/Users/YourName/nanomito/preprocessing

# Auto-detect latest run
./wf-uplgo.sh

# Specific run directory
./wf-uplgo.sh /mnt/c/data/run_dir

# Dry run (preview what will be uploaded)
./wf-uplgo.sh --dry-run

# Custom destination
./wf-uplgo.sh -u myuser -h your.ssh.host -d /scratch/myuser/workbench/
```

**Parameters:**

- `[RUN_DIRECTORY]` - Path to run directory (auto-detects latest if omitted)
- `-u|--user USER` - SSH username (default: from config)
- `-h|--host HOST` - SSH hostname (default: from config)
- `-d|--dest PATH` - Destination path on remote host
- `-n|--dry-run` - Show what would be transferred without actually doing it
- `--help` - Display help message

**What gets uploaded:**

- ✅ Configuration files (sample_sheet, etc.)
- ✅ Logs and metadata
- ✅ `pod5_chrM/` directory (filtered Pod5 + dictionaries)
- ❌ Raw `pod5/` files (excluded)
- ❌ `bam/` files (excluded)
- ❌ `fastq_pass/`, `fastq_fail/` (excluded)

**Time:** ~5-15 minutes depending on network speed

---

#### 4. **submit_preprocessing.ps1** (Windows/PowerShell)

**Purpose:** Orchestrate the complete preprocessing pipeline.

**Features:**

- Runs all three steps in sequence
- Automatic latest run detection
- Skip individual steps if needed
- Dry-run mode for testing
- Comprehensive error handling

**Usage:**

```powershell
# Complete pipeline on latest run
.\submit_preprocessing.ps1

# Specific run directory
.\submit_preprocessing.ps1 -RunDirectory "C:\data\run_dir"

# Skip basecalling (already done)
.\submit_preprocessing.ps1 -SkipDorado

# Skip mitochondrial extraction
.\submit_preprocessing.ps1 -SkipMitochondrial

# Skip upload
.\submit_preprocessing.ps1 -SkipUpload

# Dry run (preview execution)
.\submit_preprocessing.ps1 -DryRun

# Help
.\submit_preprocessing.ps1 -Help
```

**Parameters:**

- `-RunDirectory` - Run directory path
- `-SkipDorado` - Skip basecalling step
- `-SkipMitochondrial` - Skip chrM extraction step
- `-SkipUpload` - Skip upload to HPC
- `-DryRun` - Preview without execution
- `-Help` - Show help information

**Time:** ~2-5 hours for complete pipeline

---

### Configuration Files

#### 1. `preprocessing.config` (Bash/Linux/WSL)

Configuration file for Bash scripts running on Linux, WSL, or HPC environments.

**Used by:**

- `wf-getmt.sh` - Mitochondrial read extraction
- `wf-uplgo.sh` - Upload to HPC cluster

**Usage in scripts:**

```bash
# Source the configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/preprocessing.config"

# Now use the variables
source "$CONDA_SCRIPT"
conda activate "$GETMT_ENV"
```

**Key variables:**

- `CONDA_SCRIPT` - Path to conda initialization
- `GETMT_ENV` - Conda environment name
- `CHRMPIDS_SCRIPT` - Python script for chrM read ID extraction
- `CREATE_PID_DICT_SCRIPT` - Python script for PID dictionary creation
- `DATA_ROOT` - Root directory for run data
- `GO_USER`, `GO_HOST` - HPC connection settings

#### 2. `preprocessing.ps1` (PowerShell/Windows)

Configuration file for PowerShell scripts running on Windows.

**Used by:**

- `wf-prebchg.ps1` - Dorado basecaller execution (preprocessing before basecalling)
- `submit_preprocessing.ps1` - Complete pipeline orchestration

**Usage in scripts:**

```powershell
# Dot-source the configuration file
. "$PSScriptRoot\preprocessing.ps1"

# Now use the variables
$doradoPath = Join-Path $DoradoBasePath $DoradoExecutable
```

**Key variables:**

- `DoradoBasePath`, `DoradoExecutable` - Dorado installation paths
- `DoradoModel`, `DoradoKit` - Default basecalling settings
- `DataRoot` - Root directory for run data
- `ReferencePath` - Human reference genome path
- `DoradoScript`, `MitochondrialScript`, `UploadScript` - Workflow script paths

## Configuration

### First-time Setup

1. **For Linux/WSL/HPC:**

   ```bash
   cd preprocessing/
   nano preprocessing.config
   ```

   Update paths to match your environment:
   - `CONDA_SCRIPT` - Your conda installation path
   - `CHRMPIDS_SCRIPT`, `CREATE_PID_DICT_SCRIPT` - Python script locations
   - `DATA_ROOT` - Your data directory
   - `GO_USER`, `GO_HOST` - Your HPC credentials

1. **For Windows:**

   ```powershell
   cd preprocessing/
   notepad preprocessing.ps1
   ```

   Update paths to match your environment:
   - `DoradoBasePath`, `DoradoExecutable` - Your Dorado installation
   - `DataRoot` - Your data directory
   - `ReferencePath` - Your reference genome location
   - `DoradoScript`, `MitochondrialScript`, `UploadScript` - Your script locations

### Version Updates

When updating Dorado or other tools, only modify the configuration files:

```powershell
# In preprocessing.ps1, update:
$Script:DoradoExecutable = "dorado-1.2.0-win64\bin\dorado.exe"
```

All scripts using this configuration will automatically use the new version.

## Benefits

- **Centralized configuration**: Change paths in one place
- **Environment-specific**: Separate configs for Windows vs Linux
- **Easy maintenance**: Update tool versions without modifying scripts
- **Version control friendly**: Track configuration changes separately from code
- **Multi-user support**: Each user can maintain their own configuration

## Migration from Hardcoded Values

All scripts have been updated to use centralized configuration files.

**Migration status:**

- [x] `wf-getmt.sh` - ✅ Sources `preprocessing.config`
- [x] `wf-uplgo.sh` - ✅ Sources `preprocessing.config`
- [x] `wf-prebchg.ps1` - ✅ Dot-sources `preprocessing.ps1`
- [x] `submit_preprocessing.ps1` - ✅ Dot-sources `preprocessing.ps1`

**Benefits:**

- No hardcoded paths in any workflow script
- Single point of configuration per platform (Windows/Linux)
- Easy to update tool versions
- Multi-user and multi-environment support

---

## Installation & Setup

### 1. Install Prerequisites

**Windows:**

```powershell
# Install Dorado (download from ONT)
# Extract to C:\Users\YourName\bioapps\dorado-X.X.X-win64\

# Install WSL2
wsl --install
```

**WSL/Linux:**

<!-- markdownlint-disable MD034 -->
```bash
# In WSL, install Conda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh

# Follow the installer prompts, then restart your terminal
```
<!-- markdownlint-enable MD034 -->

### 2. Configure SSH for your remote host

```bash
# In WSL, generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your.email@domain.com"

# Copy public key to your SSH host
ssh-copy-id your_username@your.ssh.host

# Test connection (should not ask for password)
ssh your_username@your.ssh.host
```

**Note on SSH authentication:**

The upload workflow (`wf-uplgo.sh`) will automatically:

- Connect to an existing `ssh-agent` or start a new one
- Prompt **once** for your SSH key passphrase if needed
- Reuse the key for all subsequent operations
- Clean up the agent on exit

You will be prompted for:

1. **Pipeline confirmation** at start (one-time, to validate all steps)
2. **SSH passphrase** during upload if key not already loaded (one-time)

No redundant confirmations or multiple passphrase prompts.

### 3. Create Conda Environment

Create a dedicated conda environment with all required tools:

```bash
# In WSL
conda create -n nanomito python=3.9
conda activate nanomito

# Install required packages
conda install -c bioconda pysam samtools
pip install pod5

# Verify installation
python -c "import pysam; print('pysam:', pysam.__version__)"
python -c "import pod5; print('pod5:', pod5.__version__)"
pod5 --version
samtools --version
```

**Environment contents (nanomito):**

| Package | Version | Purpose |
| --------- | --------- | --------- |
| `python` | 3.9+ | Base interpreter |
| `pysam` | Latest | BAM file manipulation |
| `pod5` | Latest | Pod5 file filtering |
| `samtools` | Latest | BAM file processing |

**Note:** The environment name `nanomito` is referenced in `preprocessing.config` (`GETMT_ENV` variable).

### 4. Update Configuration Files

Edit both configuration files to match your environment (see Configuration section above).

### 5. Test Installation

```powershell
# Test Dorado
.\wf-prebchg.ps1 -Help

# Test WSL scripts
wsl ./preprocessing/wf-getmt.sh --help
wsl ./preprocessing/wf-uplgo.sh --help

# Test conda environment (in WSL)
wsl bash -c "source ~/anaconda3/etc/profile.d/conda.sh && conda activate nanomito && python -c 'import pysam, pod5; print(\"Environment OK\")'"
```

---

## Directory Structure

After running the preprocessing pipeline, your run directory will have:

```text
run_directory/
├── pod5/                        # Original POD5 files (raw signal)
│   └── *.pod5
├── bam/                         # Dorado basecalling output
│   ├── barcode01.bam
│   ├── barcode02.bam
│   └── dorado_run.log
├── pod5_chrM/                   # Filtered chrM reads (for HPC)
│   ├── <RUN_ID>.chrM.pod5      # Filtered Pod5
│   ├── <RUN_ID>.pid_dict.tsv   # Read-to-parent ID mapping ⚠️ REQUIRED
│   ├── <RUN_ID>.chrM_pids.txt  # List of parent IDs
│   └── <RUN_ID>.wf-getmt.log   # Extraction log
└── sample_sheet_*.csv           # ONT sample sheet
```

**Important:** The `pid_dict.tsv` file must be present for the HPC workflows to run correctly.

---

## Troubleshooting

### Common Issues

#### 1. "Dorado executable not found"

**Solution:** Check and update `DoradoBasePath` and `DoradoExecutable` in `preprocessing.config`

```powershell
# Verify path exists
Test-Path "C:\path\to\your\dorado\installation\dorado-1.3.0-win64\bin\dorado.exe"
```

#### 2. "Failed to load Conda"

**Solution:** Update `CONDA_SCRIPT` path in `preprocessing.config`

```bash
# In WSL, find conda script location
which conda
# Output example: /home/yourusername/anaconda3/bin/conda

# The conda.sh script is typically in:
ls /home/yourusername/anaconda3/etc/profile.d/conda.sh

# Update CONDA_SCRIPT in preprocessing.config to match your path
```

#### 3. "ModuleNotFoundError: No module named 'pysam'" or "pod5"

**Problem:** Required Python packages not installed in conda environment

**Solution:** Activate the environment and install missing packages:

```bash
# In WSL
source ~/anaconda3/etc/profile.d/conda.sh
conda activate nanomito

# Install missing packages
conda install -c bioconda pysam samtools
pip install pod5

# Verify installation
python -c "import pysam, pod5; print('OK')"
```

#### 4. "No run directories found"

**Problem:** Auto-detection expects directories matching pattern `YYMMDD_*`

**Solution:** Specify run directory explicitly or rename directory:

```powershell
.\submit_preprocessing.ps1 -RunDirectory "C:\data\your_run_name"
```

#### 5. "SSH connection failed" during upload

**Solution:** Ensure SSH key is set up correctly

```bash
# In WSL, test SSH connection
ssh your_username@your.ssh.host

# If prompted for password, re-run ssh-copy-id
ssh-copy-id your_username@your.ssh.host
```

#### 6. "pid_dict.tsv is empty or missing"

**Problem:** BAM files don't contain necessary read tags

**Solution:** Ensure `wf-prebchg.ps1` completed successfully and BAM files are valid:

```powershell
# Check BAM files exist
dir C:\data\your_run\bam\*.bam

# Check log file
type C:\data\your_run\bam\dorado_run.log
```

#### 7. WSL path conversion issues

**Problem:** Windows paths like `C:\data\run` don't work in WSL

**Solution:** Convert to WSL format:

- Windows: `C:\data\run` → WSL: `/mnt/c/data/run`
- Windows: `D:\data\run` → WSL: `/mnt/d/data/run`

---

## Performance Tips

### Optimize Basecalling

- Use `hac` model for balance between speed and accuracy
- Use `sup` model only if highest accuracy is required (~3x slower)
- Ensure GPU drivers are up to date
- Close other GPU-intensive applications

### Optimize Upload

- Run upload during off-peak hours for better network speed
- Use `--dry-run` first to estimate transfer size and time
- Compress large files before upload if needed

### Disk Space Management

- Basecalling: Requires ~50-100% of POD5 size for BAM output
- chrM extraction: Requires ~10-20% of original POD5 size
- Keep at least 200GB free space before starting

---

## Integration with Main Nanomito Workflow

After preprocessing completes and data is uploaded to HPC cluster:

```bash
# On HPC cluster
cd /scratch/your_username/workbench/run_dir

# Verify required files are present
ls -lh pod5_chrM/*.pid_dict.tsv
ls -lh pod5_chrM/*.chrM.pod5

# Run main Nanomito workflow
/path/to/nanomito/submit_nanomito.sh .
```

See main [README.md](../README.md) for HPC workflow documentation.

---

## Version History

- **25.11.10** - Improved README with comprehensive documentation
- **25.11.09** - Renamed scripts to workflow naming convention (wf-*)
- **25.11.04** - Added centralized configuration files
- **25.10.27** - Added preprocessing workflows
- **25.09.19** - Initial wf-getmt.sh script

---

## Author

**Marc FERRE**  
Email: <marc.ferre@univ-angers.fr>  
Institution: CNRS UMR6015 / INSERM UMR1083
