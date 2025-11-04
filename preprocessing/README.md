# Preprocessing Configuration Files

This directory contains two configuration files to centralize settings for preprocessing scripts:

## Files

### 1. `preprocessing.config` (Bash/Linux/WSL)

Configuration file for Bash scripts running on Linux, WSL, or HPC environments.

**Used by:**
- `wf-getmt.sh` - Mitochondrial read extraction
- `upload_go.sh` - Upload to Genouest cluster

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
- `GO_USER`, `GO_HOST` - Genouest connection settings

### 2. `preprocessing.ps1` (PowerShell/Windows)

Configuration file for PowerShell scripts running on Windows.

**Used by:**
- `dorado_run.ps1` - Dorado basecaller execution
- `pipeline_run.ps1` - Complete pipeline orchestration

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
   - `GO_USER`, `GO_HOST` - Your Genouest credentials

2. **For Windows:**
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

Scripts are being progressively updated to use these configuration files. 
Current status:
- [ ] `wf-getmt.sh` - TODO: Update to source preprocessing.config
- [ ] `upload_go.sh` - TODO: Update to source preprocessing.config  
- [ ] `dorado_run.ps1` - TODO: Update to dot-source preprocessing.ps1
- [ ] `pipeline_run.ps1` - TODO: Update to dot-source preprocessing.ps1

See [TODO.md](../TODO.md) for tracking progress.
