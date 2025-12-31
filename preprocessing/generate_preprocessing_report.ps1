#!pwsh
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>

<#
.SYNOPSIS
    Generate HTML report for preprocessing workflow

.DESCRIPTION
    This script parses Dorado basecalling and mitochondrial extraction logs
    to generate a comprehensive HTML report with metrics and results.

.PARAMETER RunDirectory
    Path to the run directory containing pod5_chrM and bam subdirectories

.EXAMPLE
    .\generate_preprocessing_report.ps1 'C:\data\240503_Ker_Are_Imb'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunDirectory
)

# Validate run directory
if (-not (Test-Path $RunDirectory -PathType Container)) {
    Write-Error "Run directory not found: $RunDirectory"
    exit 1
}

$RUN_ID = Split-Path $RunDirectory -Leaf
$POD5_CHR_DIR = Join-Path $RunDirectory "pod5_chrM"
$BAM_DIR = Join-Path $RunDirectory "bam"
$REPORT_FILE = Join-Path $POD5_CHR_DIR "preprocessing_report-$RUN_ID.html"

# Validate required directories
if (-not (Test-Path $POD5_CHR_DIR -PathType Container)) {
    Write-Error "pod5_chrM directory not found: $POD5_CHR_DIR"
    exit 1
}

# Parse Dorado log
$DORADO_LOG = $null
$possibleLogPaths = @(
    (Join-Path $BAM_DIR "dorado_run.log"),
    (Join-Path $POD5_CHR_DIR "$RUN_ID.wf-prebchg.log"),
    (Join-Path $RunDirectory "dorado_run.log")
)

foreach ($logPath in $possibleLogPaths) {
    if (Test-Path $logPath -PathType Leaf) {
        $DORADO_LOG = $logPath
        break
    }
}

$DORADO_METRICS = @{
    BasecalledReads = 0
    FilteredReads = 0
    Duration = "N/A"
    GPU = "N/A"
    DoradoVersion = "N/A"
    ChunkSize = "N/A"
    BatchSize = "N/A"
    SamplesPerSecond = "N/A"
}

if ($DORADO_LOG -and (Test-Path $DORADO_LOG -PathType Leaf)) {
    $content = Get-Content $DORADO_LOG -Raw
    
    # Extract basecalled reads
    if ($content -match "Simplex reads basecalled:\s*(\d+)") {
        $DORADO_METRICS.BasecalledReads = [int]$matches[1]
    }
    
    # Extract filtered reads
    if ($content -match "Simplex reads filtered:\s*(\d+)") {
        $DORADO_METRICS.FilteredReads = [int]$matches[1]
    }
    
    # Extract duration
    if ($content -match "Basecalling completed successfully in\s+([0-9:]+)") {
        $DORADO_METRICS.Duration = $matches[1]
    }
    
    # Extract GPU info
    if ($content -match "cuda:\d+\s+-\s+(.+)(?:\r?\n|$)") {
        $DORADO_METRICS.GPU = $matches[1].Trim()
    }
    
    # Extract Dorado version
    if ($content -match "Dorado version:\s+([^\r\n]+)") {
        $DORADO_METRICS.DoradoVersion = $matches[1].Trim()
    }
    
    # Extract chunk and batch size
    if ($content -match "cuda:0 using chunk size\s+(\d+),\s+batch size\s+(\d+)") {
        $DORADO_METRICS.ChunkSize = $matches[1]
        $DORADO_METRICS.BatchSize = $matches[2]
    }
    
    # Extract samples per second
    if ($content -match "Basecalled @\s+Samples/s:\s+([0-9.e+-]+)") {
        $samplesPerSec = [double]$matches[1]
        if ($samplesPerSec -gt 1e7) {
            $DORADO_METRICS.SamplesPerSecond = "{0:F2}M" -f ($samplesPerSec / 1e6)
        } else {
            $DORADO_METRICS.SamplesPerSecond = "{0:F2}K" -f ($samplesPerSec / 1e3)
        }
    }
}

# Parse mitochondrial extraction log
$GETMT_LOG = Join-Path $POD5_CHR_DIR "$RUN_ID.wf-getmt.log"
$GETMT_METRICS = @{
    TotalReads = 0
    AlignedReads = 0
    UniqueReads = 0
    SplitReads = 0
    DuplicateReads = 0
    Pod5Size = "N/A"
    Pod5Batches = 0
}

if (Test-Path $GETMT_LOG -PathType Leaf) {
    $content = Get-Content $GETMT_LOG -Raw
    
    # Extract total reads
    if ($content -match "Pod5 reads:\s*(\d+)") {
        $GETMT_METRICS.TotalReads = [int]$matches[1]
    }
    
    # Extract reads aligned to chrM
    if ($content -match "Reads aligned to chrM:\s*(\d+)") {
        $GETMT_METRICS.AlignedReads = [int]$matches[1]
    }
    
    # Extract unique reads pIDs
    if ($content -match "Unique reads pIDs:\s*(\d+)") {
        $GETMT_METRICS.UniqueReads = [int]$matches[1]
    }
    
    # Extract split reads
    if ($content -match "Split reads:\s*(\d+)") {
        $GETMT_METRICS.SplitReads = [int]$matches[1]
    }
    
    # Extract duplicate reads
    if ($content -match "Duplicate reads ignored:\s*(\d+)") {
        $GETMT_METRICS.DuplicateReads = [int]$matches[1]
    }
    
    # Extract batches and reads
    if ($content -match "Found\s+(\d+)\s+batches,\s+(\d+)\s+reads") {
        $GETMT_METRICS.Pod5Batches = [int]$matches[1]
    }
}

# Get Pod5 file size
$POD5_FILE = Join-Path $POD5_CHR_DIR "$RUN_ID.chrM.pod5"
$chrMPod5SizeBytes = 0
$chrMPod5Percent = 0
if (Test-Path $POD5_FILE -PathType Leaf) {
    $chrMPod5SizeBytes = (Get-Item $POD5_FILE).Length
    if ($chrMPod5SizeBytes -gt 1GB) {
        $GETMT_METRICS.Pod5Size = "{0:F2} GB" -f ($chrMPod5SizeBytes / 1GB)
    } elseif ($chrMPod5SizeBytes -gt 1MB) {
        $GETMT_METRICS.Pod5Size = "{0:F2} MB" -f ($chrMPod5SizeBytes / 1MB)
    } else {
        $GETMT_METRICS.Pod5Size = "{0:F2} KB" -f ($chrMPod5SizeBytes / 1KB)
    }
    
    # Calculate percentage of total Pod5 files
    if ($POD5_SIZE -gt 0) {
        $chrMPod5Percent = ($chrMPod5SizeBytes / $POD5_SIZE) * 100
    }
}

# Get BAM files info
$BAM_FILES = @()
if (Test-Path $BAM_DIR -PathType Container) {
    $BAM_FILES = Get-ChildItem -Path $BAM_DIR -Recurse -Filter "*.bam" -File -ErrorAction SilentlyContinue
}

$BAM_COUNT = $BAM_FILES.Count
$BAM_SIZE = ($BAM_FILES | Measure-Object -Property Length -Sum).Sum
if ($BAM_SIZE -gt 1GB) {
    $BAM_SIZE_STR = "{0:F2} GB" -f ($BAM_SIZE / 1GB)
} else {
    $BAM_SIZE_STR = "{0:F2} MB" -f ($BAM_SIZE / 1MB)
}

# Get total Pod5 file size
$POD5_DIR = Join-Path $RunDirectory "pod5"
$POD5_SIZE = 0
$POD5_SIZE_STR = "N/A"
if (Test-Path $POD5_DIR -PathType Container) {
    $POD5_SIZE = (Get-ChildItem -Path $POD5_DIR -Recurse -Filter "*.pod5" -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($POD5_SIZE -gt 1GB) {
        $POD5_SIZE_STR = "{0:F2} GB" -f ($POD5_SIZE / 1GB)
    } elseif ($POD5_SIZE -gt 1MB) {
        $POD5_SIZE_STR = "{0:F2} MB" -f ($POD5_SIZE / 1MB)
    } else {
        $POD5_SIZE_STR = "{0:F2} KB" -f ($POD5_SIZE / 1KB)
    }
}

# Format numbers with thousand separators
$DORADO_METRICS.BasecalledReads = "{0:N0}" -f $DORADO_METRICS.BasecalledReads
$DORADO_METRICS.FilteredReads = "{0:N0}" -f $DORADO_METRICS.FilteredReads
$GETMT_METRICS.TotalReads = "{0:N0}" -f $GETMT_METRICS.TotalReads
$GETMT_METRICS.AlignedReads = "{0:N0}" -f $GETMT_METRICS.AlignedReads
$GETMT_METRICS.UniqueReads = "{0:N0}" -f $GETMT_METRICS.UniqueReads
$GETMT_METRICS.SplitReads = "{0:N0}" -f $GETMT_METRICS.SplitReads
$GETMT_METRICS.DuplicateReads = "{0:N0}" -f $GETMT_METRICS.DuplicateReads

# Calculate filtering percentage
$filteringPercent = 0
if ($DORADO_METRICS.BasecalledReads -as [int] -gt 0) {
    $filteringPercent = ([int]$DORADO_METRICS.FilteredReads.Replace(",", "") / [int]$DORADO_METRICS.BasecalledReads.Replace(",", "")) * 100
}

$chrMPercent = 0
if ($GETMT_METRICS.TotalReads -as [int] -gt 0) {
    $chrMPercent = ([int]$GETMT_METRICS.AlignedReads.Replace(",", "") / [int]$GETMT_METRICS.TotalReads.Replace(",", "")) * 100
}

# Generate HTML
$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Preprocessing Report - $RUN_ID</title>
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
    line-height: 1.6;
    color: #333;
    max-width: 900px;
    margin: 0 auto;
    padding: 20px;
    background-color: #f5f5f5;
  }
  .container {
    background-color: white;
    border-radius: 8px;
    padding: 20px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  }
  .header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 30px 20px;
    border-radius: 8px;
    text-align: center;
    margin: -20px -20px 20px -20px;
  }
  .header h1 {
    margin: 0;
    font-size: 28px;
    font-weight: 600;
  }
  .header .run-id {
    margin-top: 10px;
    opacity: 0.9;
    font-size: 14px;
    font-family: 'Courier New', Consolas, monospace;
  }
  .section {
    margin: 25px 0;
    padding: 20px;
    background-color: #f8f9fa;
    border-left: 4px solid #667eea;
    border-radius: 4px;
  }
  .section-title {
    font-size: 18px;
    font-weight: 600;
    color: #667eea;
    margin: 0 0 20px 0;
    display: flex;
    align-items: center;
  }
  .section-title::before {
    content: '◆';
    margin-right: 10px;
    font-size: 12px;
  }
  .metric-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 15px;
  }
  .metric-box {
    background-color: white;
    padding: 12px;
    border-radius: 6px;
    border: 1px solid #dee2e6;
  }
  .metric-label {
    color: #6c757d;
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 5px;
  }
  .metric-value {
    font-family: 'Courier New', Consolas, monospace;
    font-size: 18px;
    font-weight: 700;
    color: #667eea;
  }
  .metric-subtext {
    font-size: 12px;
    color: #6c757d;
    margin-top: 3px;
  }
  .success { color: #28a745; }
  .warning { color: #ffc107; }
  .error { color: #dc3545; }
  .info { color: #17a2b8; }
  .progress-bar {
    width: 100%;
    height: 6px;
    background-color: #e9ecef;
    border-radius: 3px;
    margin-top: 8px;
    overflow: hidden;
  }
  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
    border-radius: 3px;
  }
  .file-summary {
    background-color: white;
    padding: 15px;
    border-radius: 6px;
    border: 1px solid #dee2e6;
    margin: 10px 0;
  }
  .file-name {
    font-family: 'Courier New', Consolas, monospace;
    font-size: 13px;
    color: #495057;
    margin-bottom: 5px;
  }
  .file-size {
    color: #6c757d;
    font-size: 12px;
  }
  .timestamp {
    color: #6c757d;
    font-size: 12px;
    margin-top: 15px;
    text-align: center;
  }
  @media (max-width: 600px) {
    body { padding: 10px; }
    .container { padding: 15px; }
    .header { padding: 20px 15px; margin: -15px -15px 15px -15px; }
    .header h1 { font-size: 22px; }
    .metric-grid { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
<div class="container">
  <div class="header">
    <h1>[PREPROCESSING] Nanopore Preprocessing Report</h1>
    <div class="run-id">Run: $RUN_ID</div>
  </div>

  <!-- Dorado Basecalling Section -->
  <div class="section">
    <div class="section-title">Dorado Basecalling</div>
    <div class="metric-grid">
      <div class="metric-box">
        <div class="metric-label">Reads Basecalled</div>
        <div class="metric-value success">$($DORADO_METRICS.BasecalledReads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Reads Filtered</div>
        <div class="metric-value">$($DORADO_METRICS.FilteredReads)</div>
        <div class="metric-subtext">({0:F3}% filtered)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Duration</div>
        <div class="metric-value">$($DORADO_METRICS.Duration)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">GPU Device</div>
        <div class="metric-value info">$($DORADO_METRICS.GPU)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Dorado Version</div>
        <div class="metric-value">$($DORADO_METRICS.DoradoVersion)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Throughput</div>
        <div class="metric-value">$($DORADO_METRICS.SamplesPerSecond)S/s</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Chunk Size</div>
        <div class="metric-value">$($DORADO_METRICS.ChunkSize)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Batch Size</div>
        <div class="metric-value">$($DORADO_METRICS.BatchSize)</div>
      </div>
    </div>
  </div>

  <!-- Mitochondrial Extraction Section -->
  <div class="section">
    <div class="section-title">Mitochondrial Extraction</div>
    <div class="metric-grid">
      <div class="metric-box">
        <div class="metric-label">Total Pod5 Files</div>
        <div class="metric-value info">$POD5_SIZE_STR</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Total Pod5 Reads</div>
        <div class="metric-value">$($GETMT_METRICS.TotalReads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Reads Aligned to chrM</div>
        <div class="metric-value success">$($GETMT_METRICS.AlignedReads)</div>
        <div class="progress-bar">
          <div class="progress-fill" style="width: {0:F1}%"></div>
        </div>
        <div class="metric-subtext">({0:F3}% of all reads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Unique Parent IDs</div>
        <div class="metric-value success">$($GETMT_METRICS.UniqueReads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Split Reads</div>
        <div class="metric-value warning">$($GETMT_METRICS.SplitReads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">Duplicate Reads</div>
        <div class="metric-value">$($GETMT_METRICS.DuplicateReads)</div>
      </div>
      <div class="metric-box">
        <div class="metric-label">chrM Pod5 File</div>
        <div class="metric-value">$($GETMT_METRICS.Pod5Size)</div>
        <div class="progress-bar">
          <div class="progress-fill" style="width: {0:F2}%"></div>
        </div>
        <div class="metric-subtext">($($GETMT_METRICS.Pod5Batches) batches, {0:F2}% of total Pod5)</div>
      </div>
    </div>
  </div>

  <!-- Output Files Section -->
  <div class="section">
    <div class="section-title">Output Files</div>
    <div style="margin-top: 10px;">
      <div class="file-summary">
        <div class="file-name">📊 BAM Files</div>
        <div class="metric-value">$BAM_COUNT files</div>
        <div class="file-size">Total size: $BAM_SIZE_STR</div>
      </div>
      <div class="file-summary">
        <div class="file-name">📦 chrM Pod5</div>
        <div class="metric-value">$RUN_ID.chrM.pod5</div>
        <div class="file-size">Size: $($GETMT_METRICS.Pod5Size)</div>
      </div>
      <div class="file-summary">
        <div class="file-name">📋 Logs</div>
        <div class="metric-value">pod5_chrM/</div>
        <div class="file-size">$RUN_ID.wf-prebchg.log<br/>$RUN_ID.wf-getmt.log</div>
      </div>
    </div>
  </div>

  <div class="timestamp">
    Generated on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  </div>
</div>
</body>
</html>
"@

# Replace placeholders with actual values
$filteringPercentStr = "{0:F3}" -f $filteringPercent
$chrMPercentStr = "{0:F1}" -f $chrMPercent
$chrMPod5PercentStr = "{0:F2}" -f $chrMPod5Percent
$html = $html.Replace("{0:F3}%", "$filteringPercentStr%")
$html = $html.Replace("{0:F1}%", "$chrMPercentStr%")
$html = $html.Replace("{0:F3}% of all reads", "$chrMPercentStr% of all reads")
$html = $html.Replace("{0:F2}% of total Pod5", "$chrMPod5PercentStr% of total Pod5")

# Save HTML report
$html | Out-File -FilePath $REPORT_FILE -Encoding UTF8 -Force
Write-Host "[OK] Report generated: $REPORT_FILE"
Write-Host "[METRICS]"
Write-Host "   - Basecalled reads: $($DORADO_METRICS.BasecalledReads)"
Write-Host "   - chrM reads: $($GETMT_METRICS.UniqueReads)"
Write-Host "   - BAM files: $BAM_COUNT ($BAM_SIZE_STR)"
