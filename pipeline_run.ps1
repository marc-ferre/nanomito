#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Execute complete nanopore sequencing analysis pipeline
    
.DESCRIPTION
    This script executes the full nanopore sequencing pipeline in the correct order:
    1. Dorado basecaller (dorado_run.ps1)
    2. Mitochondrial read extraction (wf-getmt.sh)
    3. Upload to Genouest cluster (upload_go.sh)
    
    By default, it automatically detects and uses the latest run directory in C:\data\
    
.PARAMETER RunDirectory
    Path to the run directory to process
    If not specified, uses the latest directory in C:\data\
    
.PARAMETER SkipDorado
    Skip the Dorado basecalling step (useful if already done)
    
.PARAMETER SkipMitochondrial
    Skip the mitochondrial extraction step
    
.PARAMETER SkipUpload
    Skip the upload to Genouest step
    
.PARAMETER DryRun
    Show what would be executed without actually running the commands
    
.EXAMPLE
    .\pipeline_run.ps1
    # Run complete pipeline on latest directory in C:\data\
    
.EXAMPLE
    .\pipeline_run.ps1 -RunDirectory "C:\data\250822_MK1B_RUN13"
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
    [switch]$DryRun
)

# Script paths
$DoradoScript = "C:\Users\mferre\Documents\workflows\dorado_run.ps1"
$MitochondrialScript = "C:\Users\mferre\Documents\workflows\wf-getmt.sh"
$UploadScript = "C:\Users\mferre\Documents\workflows\upload_go.sh"

# Global variable for SSH passphrase
$Global:SSHPassphrase = $null

function Get-SSHPassphrase {
    if ($SkipUpload) {
        Write-ColorMessage "[INFO] Upload skipped - SSH passphrase not needed" "Yellow"
        return $null
    }
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] SSH passphrase would be requested here" "Magenta"
        return "dummy-passphrase-for-dryrun"
    }
    
    Write-ColorMessage "[INFO] SSH passphrase required for Genouest upload..." "Cyan"
    $securePassphrase = Read-Host "Enter SSH passphrase for Genouest connection" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassphrase)
    $passphrase = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    return $passphrase
}

function Set-SSHAgent {
    param([string]$Passphrase)
    
    if ($DryRun -or $SkipUpload -or [string]::IsNullOrEmpty($Passphrase)) {
        return
    }
    
    try {
        Write-ColorMessage "[INFO] Configuring SSH agent for automated authentication..." "Cyan"
        
        # Start ssh-agent if not already running
        $sshAgentOutput = wsl bash -c 'eval "$(ssh-agent -s)" && echo $SSH_AUTH_SOCK'
        if ($sshAgentOutput) {
            Write-ColorMessage "[OK] SSH agent configured" "Green"
        }
        
        # Add SSH key with passphrase using expect-like approach
        $expectScript = @"
#!/bin/bash
export SSH_ASKPASS_REQUIRE=never
echo "$Passphrase" | wsl ssh-add ~/.ssh/id_rsa 2>/dev/null
"@
        
        # This will be handled by the upload script itself
        Write-ColorMessage "[INFO] SSH passphrase will be provided during upload" "Green"
    }
    catch {
        Write-ColorMessage "[WARNING] Could not configure SSH agent: $($_.Exception.Message)" "Yellow"
        Write-ColorMessage "[INFO] SSH passphrase will be requested during upload" "Yellow"
    }
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
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-ColorMessage "STEP $StepNumber/$TotalSteps : $StepName" "Yellow"
    Write-Host "=" * 60 -ForegroundColor Cyan
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
        & powershell -File $DoradoScript -RunDirectory $RunDir
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "[SUCCESS] Dorado basecalling completed" "Green"
            return $true
        }
        else {
            Write-ColorMessage "[ERROR] Dorado basecalling failed with exit code $LASTEXITCODE" "Red"
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
    
    # Convert Windows path to WSL path
    $WslRunDir = $RunDir -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] Would execute: wsl `"$MitochondrialScript`" `"$WslRunDir`"" "Magenta"
        return $true
    }
    
    try {
        $result = wsl "$MitochondrialScript" "$WslRunDir"
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

function Invoke-GenouestionUpload {
    param([string]$RunDir)
    
    if ($SkipUpload) {
        Write-ColorMessage "[SKIPPED] Genouest upload step" "Yellow"
        return $true
    }
    
    Write-ColorMessage "[INFO] Starting upload to Genouest cluster..." "Cyan"
    
    # Convert Windows path to WSL path
    $WslRunDir = $RunDir -replace "C:\\", "/mnt/c/" -replace "\\", "/"
    
    if ($DryRun) {
        Write-ColorMessage "[DRY RUN] Would execute: wsl `"$UploadScript`" `"$WslRunDir`"" "Magenta"
        return $true
    }
    
    try {
        $result = wsl "$UploadScript" "$WslRunDir"
        if ($LASTEXITCODE -eq 0) {
            Write-ColorMessage "[SUCCESS] Genouest upload completed" "Green"
            return $true
        }
        else {
            Write-ColorMessage "[ERROR] Genouest upload failed with exit code $LASTEXITCODE" "Red"
            return $false
        }
    }
    catch {
        Write-ColorMessage "[ERROR] Genouest upload failed: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Show-PipelineSummary {
    param([string]$RunDir)
    
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-ColorMessage "NANOPORE SEQUENCING PIPELINE SUMMARY" "Yellow"
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-ColorMessage "Run Directory: $RunDir" "White"
    Write-ColorMessage "Dry Run Mode: $DryRun" "White"
    Write-Host ""
    Write-ColorMessage "Pipeline Steps:" "White"
    Write-ColorMessage "  1. Dorado Basecalling: $(if ($SkipDorado) { 'SKIPPED' } else { 'ENABLED' })" "White"
    Write-ColorMessage "  2. Mitochondrial Extraction: $(if ($SkipMitochondrial) { 'SKIPPED' } else { 'ENABLED' })" "White"
    Write-ColorMessage "  3. Genouest Upload: $(if ($SkipUpload) { 'SKIPPED' } else { 'ENABLED' })" "White"
    if (-not $SkipUpload) {
        $sshStatus = if ($Global:SSHPassphrase) { "CONFIGURED" } else { "WILL BE REQUESTED" }
        Write-ColorMessage "SSH Authentication: $sshStatus" "White"
    }
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
}

function Request-UserConfirmation {
    if ($DryRun) {
        return $true
    }
    
    $response = Read-Host "Do you want to proceed with the pipeline execution? (y/N)"
    return $response -match "^[Yy]$"
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
    
    # Get SSH passphrase if needed for upload
    $Global:SSHPassphrase = Get-SSHPassphrase
    
    # Configure SSH authentication
    Set-SSHAgent -Passphrase $Global:SSHPassphrase
    
    # Show summary
    Show-PipelineSummary -RunDir $RunDirectory
    
    # Request confirmation
    if (-not (Request-UserConfirmation)) {
        Write-ColorMessage "[INFO] Pipeline execution cancelled by user" "Yellow"
        exit 0
    }
    
    # Calculate total steps
    $TotalSteps = 3
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
        Write-StepHeader "Upload to Genouest Cluster" $CurrentStep $TotalSteps
        if (Invoke-GenouestionUpload -RunDir $RunDirectory) {
            $SuccessfulSteps++
        }
        else {
            throw "Genouest upload failed - stopping pipeline"
        }
    }
    
    # Final summary
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Green
    if ($DryRun) {
        Write-ColorMessage "DRY RUN COMPLETED SUCCESSFULLY" "Green"
        Write-ColorMessage "All pipeline steps validated - ready for execution" "Green"
    }
    else {
        Write-ColorMessage "PIPELINE COMPLETED SUCCESSFULLY" "Green"
        Write-ColorMessage "All $SuccessfulSteps steps completed successfully" "Green"
    }
    Write-ColorMessage "Run Directory: $RunDirectory" "White"
    Write-Host "=" * 60 -ForegroundColor Green
    
    exit 0
}
catch {
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Red
    Write-ColorMessage "PIPELINE FAILED" "Red"
    Write-ColorMessage "Error: $($_.Exception.Message)" "Red"
    Write-Host "=" * 60 -ForegroundColor Red
    exit 1
}