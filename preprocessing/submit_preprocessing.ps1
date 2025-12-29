#!/usr/bin/env pwsh
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

<#
.SYNOPSIS
    Execute complete nanopore sequencing analysis pipeline
    
.DESCRIPTION
    This script executes the full nanopore sequencing pipeline in the correct order:
    1. Dorado basecaller (dorado_run.ps1)
    2. Mitochondrial read extraction (wf-getmt.sh)
    3. Upload to HPC cluster (upload_go.sh)
    
    By default, it automatically detects and uses the latest run directory in C:\data\
    
.PARAMETER RunDirectory
    Path to the run directory to process
    If not specified, uses the latest directory in C:\data\
    
.PARAMETER SkipDorado
    Skip the Dorado basecalling step (useful if already done)
    
.PARAMETER SkipMitochondrial
    Skip the mitochondrial extraction step
    
.PARAMETER SkipUpload
    Skip the upload to HPC cluster
    
.PARAMETER DryRun
    Show what would be executed without actually running the commands

.PARAMETER Help
    Display this help information
    
.EXAMPLE
    .\pipeline_run.ps1
    # Run complete pipeline on latest directory in C:\data\
    
.EXAMPLE
    .\pipeline_run.ps1 -Help
    # Display detailed help information
    
.EXAMPLE
    .\pipeline_run.ps1 -RunDirectory "C:\data\run_dir"
    # Run complete pipeline on specific directory
    
.EXAMPLE
    .\pipeline_run.ps1 -SkipDorado
    # Skip basecalling, only do mitochondrial extraction and upload
    
.EXAMPLE
    .\pipeline_run.ps1 -DryRun
    # Preview what would be executed
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RunDirectory,
    
    [switch]$SkipDorado,
    [switch]$SkipMitochondrial,
    [switch]$SkipUpload,
    [switch]$DryRun,
    [switch]$Help
)

# Load configuration from centralized config file
. "$PSScriptRoot\preprocessing.ps1"

# Version from git tags (fallback to 'unknown' if not in git repo)
$Version = & {
    $gitDir = Split-Path -Parent $PSScriptRoot
    try {
        $version = & git -C "$gitDir" describe --tags 2>$null
        if ($?) { return $version }
    } catch { }
    return 'unknown'
}

# Script paths (from config)
$DoradoScript = $Script:DoradoScript
$MitochondrialScript = $Script:MitochondrialScript
$UploadScript = $Script:UploadScript

function Get-SSHPassphrase {
    # SSH passphrase is entered during upload when needed
    # This function is kept for potential future automation
    return $null
}

function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-StepHeader {
    param([string]$StepName, [int]$StepNumber, [int]$TotalSteps)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-ColorMessage "STEP $StepNumber/$TotalSteps : $StepName" "Yellow"
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function Get-LatestRunDirectory {
    $DataRoot = "C:\data"
    
    if (-not (Test-Path $DataRoot)) {
        throw "Data root directory does not exist: '$DataRoot'"
    }
    
    # Find directories with date format (YYMMDD_) and sort by creation time
    $LatestDir = Get-ChildItem -Path $DataRoot -Directory | 
    Where-Object { $_.Name -match "^\d{6}_" } |
    Sort-Object CreationTime -Descending |
    Select-Object -First 1
    
    if (-not $LatestDir) {
        throw "No run directories found in '$DataRoot' (looking for format YYMMDD_*)"
    }
    
    Write-ColorMessage "[INFO] Latest run directory automatically detected: '$($LatestDir.FullName)'" "Green"
    return $LatestDir.FullName
}

function Test-Prerequisites {
    Write-ColorMessage "[INFO] Checking prerequisites..." "Cyan"
    
    # Check if scripts exist
    $Scripts = @($DoradoScript, $MitochondrialScript, $UploadScript)
    foreach ($Script in $Scripts) {
        if (-not (Test-Path $Script)) {
            throw "Required script not found: '$Script'"
        }
    }
    
    # Check if WSL is available for bash scripts
    try {
        $null = wsl --version 2>$null
        Write-ColorMessage "[OK] WSL is available for bash scripts" "Green"
    }
    catch {
        throw "WSL is required to run bash scripts but is not available"
    }
    
    Write-ColorMessage "[OK] All prerequisites met" "Green"
}

function Invoke-DoradoBasecaller {
    param([string]$RunDir)
    
    if ($SkipDorado) {
        Write-ColorMessage "[SKIPPED] Dorado basecalling step" "Yellow"
        return $true
    }
    
    Write-ColorMessage "[INFO] Starting Dorado basecalling..." "Cyan"
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] Would execute: powershell -File `"$DoradoScript`" -RunDirectory `"$RunDir`"" "Magenta"
        return $true
    }
    
    try {
        $process = Start-Process -FilePath "powershell" -ArgumentList "-File", "`"$DoradoScript`"", "-RunDirectory", "`"$RunDir`"" -Wait -PassThru -NoNewWindow
        $exitCode = $process.ExitCode
        
        if ($exitCode -eq 0) {
            Write-ColorMessage "[SUCCESS] Dorado basecalling completed" "Green"
            return $true
        }
        else {
            Write-ColorMessage "[ERROR] Dorado basecalling failed with exit code $exitCode" "Red"
            return $false
        }
    }
    catch {
        Write-ColorMessage "[ERROR] Dorado basecalling failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Invoke-MitochondrialExtraction {
    param([string]$RunDir)
    
    if ($SkipMitochondrial) {
        Write-ColorMessage "[SKIPPED] Mitochondrial extraction step" "Yellow"
        return $true
    }
    
    Write-ColorMessage "[INFO] Starting mitochondrial read extraction..." "Cyan"
    
    # Convert Windows paths to WSL paths
    $WslRunDir = $RunDir -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    $WslMitochondrialScript = $MitochondrialScript -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] Would execute: wsl `"$WslMitochondrialScript`" `"$WslRunDir`"" "Magenta"
        return $true
    }
    
    try {
        $result = wsl bash "$WslMitochondrialScript" "$WslRunDir"
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "[SUCCESS] Mitochondrial extraction completed" "Green"
            return $true
        }
        else {
            Write-ColorMessage "[ERROR] Mitochondrial extraction failed with exit code $LASTEXITCODE" "Red"
            return $false
        }
    }
    catch {
        Write-ColorMessage "[ERROR] Mitochondrial extraction failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Invoke-HpcUpload {
    param([string]$RunDir)
    
    if ($SkipUpload) {
        Write-ColorMessage "[SKIPPED] HPC upload step" "Yellow"
        return $true
    }
    
    Write-ColorMessage "[INFO] Starting upload to HPC cluster..." "Cyan"
    
    # Convert Windows paths to WSL paths
    $WslRunDir = $RunDir -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    $WslUploadScript = $UploadScript -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] Would execute: wsl `"$WslUploadScript`" `"$WslRunDir`"" "Magenta"
        return $true
    }
    
    try {
        # Build environment variable for WSL to skip upload confirmation
        $wslCommand = "export PIPELINE_MODE=true && bash `"$WslUploadScript`" `"$WslRunDir`""
        & wsl bash -c "`"$wslCommand`""
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -eq 0) {
            Write-ColorMessage "[SUCCESS] HPC upload completed" "Green"
            return $true
        }
        else {
            Write-ColorMessage "[ERROR] HPC upload failed with exit code $exitCode" "Red"
            return $false
        }
    }
    catch {
        Write-ColorMessage "[ERROR] HPC upload failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Show-PipelineSummary {
    param([string]$RunDir)
    
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-ColorMessage "NANOPORE SEQUENCING PIPELINE SUMMARY" "Yellow"
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-ColorMessage "Run Directory: $RunDir" "White"
    Write-ColorMessage "Dry Run Mode: $DryRun" "White"
    Write-Host ""
    Write-ColorMessage "Pipeline Steps:" "White"
    Write-ColorMessage "  1. Dorado Basecalling: $(if ($SkipDorado) { 'SKIPPED' } else { 'ENABLED' })" "White"
    Write-ColorMessage "  2. Mitochondrial Extraction: $(if ($SkipMitochondrial) { 'SKIPPED' } else { 'ENABLED' })" "White"
    Write-ColorMessage "  3. HPC Upload: $(if ($SkipUpload) { 'SKIPPED' } else { 'ENABLED' })" "White"
    if (-not $SkipUpload) {
        Write-ColorMessage "SSH Authentication: WILL BE HANDLED DURING UPLOAD" "White"
    }
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
}

function Request-UserConfirmation {
    if ($DryRun) {
        return $true
    }
    
    $response = Read-Host "Do you want to proceed with the pipeline execution? (y/N)"
    return $response -match "^[Yy]$"
}

# Handle help requests
if ($Help -or $RunDirectory -match "^(-h|--help|-help|\?|/\?)$") {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Main execution
try {
    Write-ColorMessage "Starting Nanopore Sequencing Analysis Pipeline" "Yellow"
    
    # Determine run directory
    if (-not $RunDirectory) {
        Write-ColorMessage "[INFO] No run directory specified, detecting latest directory..." "Cyan"
        $RunDirectory = Get-LatestRunDirectory
    }
    else {
        if (-not (Test-Path $RunDirectory)) {
            throw "Specified run directory does not exist: '$RunDirectory'"
        }
        Write-ColorMessage "[INFO] Using specified run directory: '$RunDirectory'" "Green"
    }
    
    # Check prerequisites
    Test-Prerequisites
    
    # Show summary
    Show-PipelineSummary -RunDir $RunDirectory
    
    # Request confirmation
    if (-not (Request-UserConfirmation)) {
        Write-ColorMessage "[INFO] Pipeline execution cancelled by user" "Yellow"
        exit 0
    }
    
    # Calculate total steps
    $TotalSteps = 0
    if (-not $SkipDorado) { $TotalSteps++ }
    if (-not $SkipMitochondrial) { $TotalSteps++ }
    if (-not $SkipUpload) { $TotalSteps++ }
    
    $CurrentStep = 0
    $SuccessfulSteps = 0
    
    # Execute pipeline steps
    if (-not $SkipDorado) {
        $CurrentStep++
        Write-StepHeader "Dorado Basecalling" $CurrentStep $TotalSteps
        if (Invoke-DoradoBasecaller -RunDir $RunDirectory) {
            $SuccessfulSteps++
        }
        else {
            throw "Dorado basecalling failed - stopping pipeline"
        }
    }
    
    if (-not $SkipMitochondrial) {
        $CurrentStep++
        Write-StepHeader "Mitochondrial Read Extraction" $CurrentStep $TotalSteps
        if (Invoke-MitochondrialExtraction -RunDir $RunDirectory) {
            $SuccessfulSteps++
        }
        else {
            throw "Mitochondrial extraction failed - stopping pipeline"
        }
    }
    
    if (-not $SkipUpload) {
        $CurrentStep++
        Write-StepHeader "Upload to HPC Cluster" $CurrentStep $TotalSteps
        if (Invoke-HpcUpload -RunDir $RunDirectory) {
            $SuccessfulSteps++
        }
        else {
            throw "HPC upload failed - stopping pipeline"
        }
    }
    
    # Final summary
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
    if ($DryRun) {
        Write-ColorMessage "DRY RUN COMPLETED SUCCESSFULLY" "Green"
        Write-ColorMessage "All pipeline steps validated - ready for execution" "Green"
    }
    else {
        Write-ColorMessage "PIPELINE COMPLETED SUCCESSFULLY" "Green"
        Write-ColorMessage "All $SuccessfulSteps steps completed successfully" "Green"
    }
    Write-ColorMessage "Run Directory: $RunDirectory" "White"
    Write-Host ("=" * 60) -ForegroundColor Green
    
    exit 0
}
catch {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Red
    Write-ColorMessage "PIPELINE FAILED" "Red"
    Write-ColorMessage "Error: $($_.Exception.Message)" "Red"
    Write-Host ("=" * 60) -ForegroundColor Red
    exit 1
}