#
# Preprocessing Global Configuration File (Windows/PowerShell)
#
# This file centralizes all configuration variables used across preprocessing PowerShell scripts.
# It should be dot-sourced at the beginning of each PowerShell preprocessing script.
#
# Usage:
#   . .\preprocessing\preprocessing.ps1
#   OR
#   . "$PSScriptRoot\preprocessing.ps1"
#

# ============================================================================
# DORADO CONFIGURATION
# ============================================================================

# Path to Dorado installation directory
$Script:DoradoBasePath = "C:\Users\mferre\Documents\bioapps"

# Relative path to Dorado executable from DoradoBasePath
# Update this when upgrading Dorado version
$Script:DoradoExecutable = "dorado-1.1.1-win64\bin\dorado.exe"

# Default basecalling model (fast, hac, sup)
$Script:DoradoModel = "hac"

# Default sequencing kit
$Script:DoradoKit = "SQK-NBD114-24"

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
# WORKFLOW SCRIPTS (for pipeline_run.ps1)
# ============================================================================

# Path to Dorado basecalling script
$Script:DoradoScript = "C:\Users\mferre\Documents\workflows\dorado_run.ps1"

# Path to mitochondrial extraction script (WSL)
$Script:MitochondrialScript = "C:\Users\mferre\Documents\workflows\wf-getmt.sh"

# Path to Genouest upload script (WSL)
$Script:UploadScript = "C:\Users\mferre\Documents\workflows\upload_go.sh"

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

# Current version
$Script:PreprocessingVersion = "25.11.04.1"
