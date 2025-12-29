#
# Preprocessing Global Configuration File (Windows/PowerShell)
#
# This file centralizes all configuration variables used across preprocessing PowerShell scripts.
# It should be dot-sourced at the beginning of each PowerShell preprocessing script.
#
# Configuration values are loaded from preprocessing.config file.
#
# Usage:
#   . .\preprocessing\preprocessing.ps1
#   OR
#   . "$PSScriptRoot\preprocessing.ps1"
#

# ============================================================================
# LOAD CONFIGURATION FROM preprocessing.config
# ============================================================================

# Find and load preprocessing.config
$ConfigPath = "$PSScriptRoot\preprocessing.config"
if (-Not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    exit 1
}

# Load configuration file
$configContent = Get-Content $ConfigPath -Raw
# Parse bash variable assignments
$configLines = $configContent -split "`n" | Where-Object { $_ -match "^[A-Z_]+='" }

foreach ($line in $configLines) {
    if ($line -match "^([A-Z_]+)='(.*)'\s*$") {
        $varName = $matches[1]
        $varValue = $matches[2]
        
        # Convert bash variable names to PowerShell
        $psVarName = switch ($varName) {
            'DORADO_BASE_PATH'  { 'DoradoBasePath' }
            'DORADO_EXECUTABLE' { 'DoradoExecutable' }
            'DORADO_MODEL'      { 'DoradoModel' }
            'DORADO_KIT'        { 'DoradoKit' }
            default             { $varName }
        }
        
        New-Variable -Name $psVarName -Value $varValue -Scope Script -Force
    }
}

# ============================================================================
# DORADO CONFIGURATION
# ============================================================================

# Values loaded from preprocessing.config above
# $Script:DoradoBasePath
# $Script:DoradoExecutable  
# $Script:DoradoModel
# $Script:DoradoKit

# ============================================================================
# DATA DIRECTORIES
# ============================================================================

# Root directory for run data
$Script:DataRoot = "C:\data"

# ============================================================================
# REFERENCE FILES
# ============================================================================

# Path to human reference genome (GRCh38/hg38)
$Script:ReferencePath = "C:\data\reference\Homo_sapiens-hg38-GRCh38.p14.mmi"

# ============================================================================
# WORKFLOW SCRIPTS (for submit_preprocessing.ps1)
# ============================================================================

# Path to Dorado basecalling script (preprocessing before basecalling)
$Script:DoradoScript = "C:\Users\mferre\nanomito\preprocessing\wf-prebchg.ps1"

# Path to mitochondrial extraction script (WSL)
$Script:MitochondrialScript = "C:\Users\mferre\nanomito\preprocessing\wf-getmt.sh"

# Path to HPC upload script (WSL)
$Script:UploadScript = "C:\Users\mferre\nanomito\preprocessing\wf-uplgo.sh"

# ============================================================================
# LOGGING
# ============================================================================

# Default log file name pattern
$Script:DefaultLogPattern = ".\{0}_run.log"  # {0} will be replaced with script name

# ============================================================================
# SCRIPT METADATA
# ============================================================================

# Default author information
$Script:PreprocessingAuthor = "Marc FERRE <marc.ferre@univ-angers.fr>"
