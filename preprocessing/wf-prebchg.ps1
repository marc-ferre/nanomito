#!pwsh
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

<#
.SYNOPSIS
    Script to run Dorado basecaller with error handling and flexible parameters

.DESCRIPTION
    This script runs Dorado basecaller with robust error handling, input validation,
    and configurable parameters to process nanopore sequencing data.

.PARAMETER DoradoBasePath
    Path to Dorado installation (default: loaded from preprocessing.ps1)

.PARAMETER DoradoExecutable
    Relative path to Dorado executable from DoradoBasePath (default: loaded from preprocessing.ps1)

.PARAMETER RunDirectory
    Path to main run directory (default: automatic detection of latest directory)

.PARAMETER InputPath
    Path to directory containing POD5 files (deduced from RunDirectory if not specified)

.PARAMETER OutputPath
    Path to output directory for BAM files (deduced from RunDirectory if not specified)

.PARAMETER SampleSheet
    Path to sample sheet CSV file (automatic search in RunDirectory if not specified)

.PARAMETER ReferencePath
    Path to genomic reference file (default: loaded from preprocessing.ps1)

.PARAMETER Model
    Basecalling model to use (default: hac)

.PARAMETER Kit
    Sequencing kit used (default: SQK-NBD114-24)

.PARAMETER LogPath
    Path to log file (default: .\dorado_run.log)

.EXAMPLE
    .\cmd.ps1
    Runs the script with automatic detection of the latest run directory in C:\data\

.EXAMPLE
    .\cmd.ps1 -RunDirectory "C:\data\run_dir"
    Runs the script with a specific run directory

.EXAMPLE
    .\cmd.ps1 -RunDirectory "C:\data\my_run" -Model "sup"
    Runs the script with a custom directory and high accuracy model

.EXAMPLE
    .\cmd.ps1 -DoradoExecutable "dorado-1.2.0-win64\bin\dorado.exe"
    Runs the script with a different version of Dorado
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Path to Dorado installation")]
    [string]$DoradoBasePath = "",
    
    [Parameter(HelpMessage = "Relative path to Dorado executable from DoradoBasePath")]
    [string]$DoradoExecutable = "",
    
    [Parameter(HelpMessage = "Path to main run directory (default: automatic detection of latest directory in C:\data\)")]
    [string]$RunDirectory = "",
    
    [Parameter(HelpMessage = "Path to directory containing POD5 files (deduced from RunDirectory if not specified)")]
    [string]$InputPath = "",
    
    [Parameter(HelpMessage = "Path to output directory for BAM files (deduced from RunDirectory if not specified)")]
    [string]$OutputPath = "",
    
    [Parameter(HelpMessage = "Path to sample sheet CSV file (automatic search in RunDirectory if not specified)")]
    [string]$SampleSheet = "",
    
    [Parameter(HelpMessage = "Path to genomic reference file")]
    [string]$ReferencePath = "",
    
    [Parameter(HelpMessage = "Basecalling model to use")]
    [ValidateSet("fast", "hac", "sup")]
    [string]$Model = "",
    
    [Parameter(HelpMessage = "Sequencing kit used")]
    [string]$Kit = "",
    
    [Parameter(HelpMessage = "Path to log file")]
    [string]$LogPath = ".\dorado_run.log",
    
    [Parameter(HelpMessage = "Show help")]
    [switch]$Help
)

# ============================================================================
# Load centralized configuration
# ============================================================================
$configPath = Join-Path $PSScriptRoot "preprocessing.ps1"
if (Test-Path $configPath) {
    . $configPath
    
    # Use config values as defaults if parameters not specified
    if ([string]::IsNullOrEmpty($DoradoBasePath)) { $DoradoBasePath = $Script:DoradoBasePath }
    if ([string]::IsNullOrEmpty($DoradoExecutable)) { $DoradoExecutable = $Script:DoradoExecutable }
    if ([string]::IsNullOrEmpty($ReferencePath)) { $ReferencePath = $Script:ReferencePath }
    if ([string]::IsNullOrEmpty($Model)) { $Model = $Script:DoradoModel }
    if ([string]::IsNullOrEmpty($Kit)) { $Kit = $Script:DoradoKit }
} else {
    Write-Warning "Configuration file not found: $configPath"
    Write-Warning "Using command-line parameters or script defaults"
}

# Version from git tags (fallback to 'unknown' if not in git repo)
$Version = & {
    $gitDir = Split-Path -Parent $PSScriptRoot
    try {
        $version = & git -C "$gitDir" describe --tags 2>$null
        if ($?) { return $version }
    } catch { }
    return 'unknown'
}

# Fallback defaults if no config file
if ([string]::IsNullOrEmpty($DoradoBasePath)) { $DoradoBasePath = "C:\Users\mferre\bioapps" }
if ([string]::IsNullOrEmpty($DoradoExecutable)) { $DoradoExecutable = "dorado-1.2.0-win64\bin\dorado.exe" }
if ([string]::IsNullOrEmpty($ReferencePath)) { $ReferencePath = "C:\data\reference\Homo_sapiens-hg38-GRCh38.p14.mmi" }
if ([string]::IsNullOrEmpty($Model)) { $Model = "hac" }
if ([string]::IsNullOrEmpty($Kit)) { $Kit = "SQK-NBD114-24" }

# Show help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Function to automatically detect the latest run directory
function Get-LatestRunDirectory {
    param(
        [string]$DataRoot = $Script:DataRoot
    )
    
    if (-not (Test-Path $DataRoot)) {
        Write-Log "Root directory $DataRoot does not exist" -Level "WARNING"
        return $null
    }
    
    # Get all directories, sorted by creation date (most recent first)
    $latestDir = Get-ChildItem -Path $DataRoot -Directory | 
    Where-Object { $_.Name -match "^\d{6}_" } |  # Filter directories with date format
    Sort-Object CreationTime -Descending | 
    Select-Object -First 1
    
    if ($latestDir) {
        Write-Log "Run directory automatically detected: $($latestDir.FullName)" -Level "INFO"
        return $latestDir.FullName
    }
    else {
        Write-Log "No run directory found in $DataRoot" -Level "WARNING"
        return $null
    }
}

# Function to automatically search for sample sheet
function Find-SampleSheet {
    param(
        [string]$RunDirectory
    )
    
    if (-not (Test-Path $RunDirectory)) {
        return $null
    }
    
    # Search for CSV files that look like a sample sheet
    $sampleSheets = Get-ChildItem -Path $RunDirectory -Filter "*.csv" | 
    Where-Object { $_.Name -match "(sample_sheet|samplesheet)" }
    
    if ($sampleSheets.Count -gt 0) {
        $selectedSheet = $sampleSheets[0].FullName
        Write-Log "Sample sheet found automatically: $selectedSheet" -Level "INFO"
        return $selectedSheet
    }
    else {
        Write-Log "No sample sheet found in $RunDirectory" -Level "WARNING"
        return $null
    }
}

# Logging configuration
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Colors for console display
    $color = switch ($Level) {
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
    }
    
    Write-Host $logMessage -ForegroundColor $color
    Add-Content -Path $LogPath -Value $logMessage
}

# Path validation function
function Test-PathExists {
    param(
        [string]$Path,
        [string]$Description,
        [switch]$IsFile
    )
    
    if ($IsFile) {
        if (-not (Test-Path $Path -PathType Leaf)) {
            Write-Log "Error: File $Description does not exist: $Path" -Level "ERROR"
            return $false
        }
    }
    else {
        if (-not (Test-Path $Path -PathType Container)) {
            Write-Log "Error: Directory $Description does not exist: $Path" -Level "ERROR"
            return $false
        }
    }
    
    Write-Log "$Description validated: $Path" -Level "SUCCESS"
    return $true
}

# Main function
function Invoke-DoradoBasecaller {
    try {
        Write-Log "=== Starting Dorado Basecaller execution ===" -Level "INFO"
        
        # Determine run directory
        if ([string]::IsNullOrEmpty($RunDirectory)) {
            $RunDirectory = Get-LatestRunDirectory
            if ([string]::IsNullOrEmpty($RunDirectory)) {
                throw "Unable to determine run directory. Please specify the -RunDirectory parameter."
            }
        }
        
        Write-Log "Run directory used: $RunDirectory" -Level "INFO"
        
        # Deduce paths if not specified
        if ([string]::IsNullOrEmpty($InputPath)) {
            $InputPath = Join-Path $RunDirectory "pod5"
        }
        
        if ([string]::IsNullOrEmpty($OutputPath)) {
            $OutputPath = Join-Path $RunDirectory "bam"
        }
        
        if ([string]::IsNullOrEmpty($SampleSheet)) {
            $SampleSheet = Find-SampleSheet -RunDirectory $RunDirectory
            if ([string]::IsNullOrEmpty($SampleSheet)) {
                throw "Unable to find a sample sheet in $RunDirectory. Please specify the -SampleSheet parameter."
            }
        }
        
        Write-Log "Paths used:" -Level "INFO"
        Write-Log "  - Input (POD5): $InputPath" -Level "INFO"
        Write-Log "  - Output (BAM): $OutputPath" -Level "INFO"
        Write-Log "  - Sample Sheet: $SampleSheet" -Level "INFO"
        Write-Log "Model: $Model | Kit: $Kit" -Level "INFO"
        
        # Build path to Dorado executable
        $doradoExe = Join-Path $DoradoBasePath $DoradoExecutable
        
        # Validate all required paths
        $validationErrors = 0
        
        if (-not (Test-PathExists -Path $doradoExe -Description "Dorado executable" -IsFile)) {
            $validationErrors++
        }
        
        if (-not (Test-PathExists -Path $InputPath -Description "POD5 input directory")) {
            $validationErrors++
        }
        
        if (-not (Test-PathExists -Path $SampleSheet -Description "Sample sheet" -IsFile)) {
            $validationErrors++
        }
        
        if (-not (Test-PathExists -Path $ReferencePath -Description "Reference file" -IsFile)) {
            $validationErrors++
        }
        
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputPath)) {
            Write-Log "Creating output directory: $OutputPath" -Level "INFO"
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }
        
        if ($validationErrors -gt 0) {
            throw "Validation failed: $validationErrors error(s) detected"
        }
        
        # Check available disk space
        $outputDrive = Split-Path $OutputPath -Qualifier
        $freeSpace = (Get-WmiObject -Class Win32_LogicalDisk | Where-Object DeviceID -eq $outputDrive).FreeSpace
        $freeSpaceGB = [math]::Round($freeSpace / 1GB, 2)
        Write-Log "Free space on $outputDrive : $freeSpaceGB GB" -Level "INFO"
        
        if ($freeSpaceGB -lt 10) {
            Write-Log "Warning: Low disk space ($freeSpaceGB GB)" -Level "WARNING"
        }
        
        # Build and execute Dorado command
        Write-Log "Starting basecalling..." -Level "INFO"
        $startTime = Get-Date
        
        $arguments = @(
            "basecaller"
            $Model
            "`"$InputPath`""
            "--recursive"
            "--sample-sheet", "`"$SampleSheet`""
            "--reference", "`"$ReferencePath`""
            "--output-dir", "`"$OutputPath`""
        )
        
        Write-Log "Command: $doradoExe $($arguments -join ' ')" -Level "INFO"
        
        # Capture Dorado output to a temp log file (stdout + stderr)
        $doradoLogPath = Join-Path ([System.IO.Path]::GetTempPath()) "dorado_$([System.Guid]::NewGuid().ToString()).log"
        Write-Log "Dorado log: $doradoLogPath" -Level "INFO"
        
        # Use cmd.exe to invoke Dorado with output redirection (bypasses PowerShell pipes issue)
        # Build single-line command string for cmd.exe /c  
        $cmdString = "`"$doradoExe`" basecaller $Model `"$InputPath`" --recursive --sample-sheet `"$SampleSheet`" --reference `"$ReferencePath`" --output-dir `"$OutputPath`" > `"$doradoLogPath`" 2>&1"
        
        Write-Log "Executing: $cmdString" -Level "INFO"
        Write-Log "Executing Dorado basecaller via cmd.exe..." -Level "INFO"
        & cmd.exe /c $cmdString | Out-Null
        
        # Check if Dorado succeeded by verifying output exists
        $endTime = Get-Date
        $duration = $endTime - $startTime
        
        if (Test-Path $OutputPath) {
            Write-Log "Basecalling completed successfully in $($duration.ToString('hh\:mm\:ss'))" -Level "SUCCESS"
            Write-Log "Output files in: $OutputPath" -Level "SUCCESS"
            
            # Move Dorado log file to output directory
            try {
                $doradoLogDestination = Join-Path $OutputPath "dorado_full.log"
                if (Test-Path $doradoLogPath) {
                    Write-Log "Moving Dorado log to: $doradoLogDestination" -Level "INFO"
                    Move-Item -Path $doradoLogPath -Destination $doradoLogDestination -Force
                    Write-Log "Dorado log file saved successfully" -Level "SUCCESS"
                }
            }
            catch {
                Write-Log "Error moving Dorado log: $($_.Exception.Message)" -Level "WARNING"
            }
            
            # Move main log file to output directory
            try {
                $logDestination = Join-Path $OutputPath (Split-Path $LogPath -Leaf)
                if (Test-Path $LogPath) {
                    Write-Log "Moving log file to: $logDestination" -Level "INFO"
                    Move-Item -Path $LogPath -Destination $logDestination -Force
                    Write-Log "Log file moved successfully" -Level "SUCCESS"
                }
            }
            catch {
                Write-Log "Error moving log file: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        else {
            throw "Dorado basecalling produced no output in $OutputPath"
        }
    }
    catch {
        Write-Log "Critical error: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "ERROR"
        exit 1
    }
    finally {
        Write-Log "=== End of execution ===" -Level "INFO"
        
        # If execution ended with an error and log was not moved
        # try to move it anyway if output directory exists
        if (Test-Path $LogPath -ErrorAction SilentlyContinue) {
            try {
                if ((Test-Path $OutputPath -ErrorAction SilentlyContinue)) {
                    $logDestination = Join-Path $OutputPath (Split-Path $LogPath -Leaf)
                    Write-Log "Final log file move to: $logDestination" -Level "INFO"
                    Move-Item -Path $LogPath -Destination $logDestination -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # Silently ignore final move errors
            }
        }
    }
}

# Main entry point
Write-Log "Initializing Dorado Basecaller script" -Level "INFO"
Invoke-DoradoBasecaller