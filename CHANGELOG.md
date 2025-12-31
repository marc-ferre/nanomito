# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.4] - 2025-12-31

### Added

- HTML report generator for preprocessing workflow with comprehensive metrics
- Progress bar visualization for chrM Pod5 percentage
- Percentage of total Pod5 files in chrM Pod5 File metric
- Total Pod5 Files size metric to mitochondrial extraction section
- Automatic cleanup of Dorado temp directories in finally block
- Dorado log copying to pod5_chrM directory with proper naming
- HTML report archiving with SHA256 checksum verification in `wf-finalize.sh`
- Preservation of directory structure when archiving per-sample HTML reports
- Automated report integrity validation using checksums

### Changed

- Removed email functionality and integrated report generation into pipeline workflow
- Report filename format from report.<RUN_ID>.html to report-<RUN_ID>.html
- Preprocessing versions now derived from git

### Fixed

- Dorado temp file cleanup from both run directory and current working directory
- Emoji characters replaced with ASCII text to fix string encoding issues
- Comprehensive temp directory cleanup patterns (both `.temp*` and `.tmp*`)
- Dorado log search in multiple locations including BAM directory
- SSH-add syntax error in conditional statement
- Detection and reporting of upload failures
- Native PowerShell command error handling with temp file capture for Dorado
- NANOMITO_DIR support in submit_nanomito.sh with suppressed submit script logs
- Reports not being archived to `/projects/nanomito/<RUN_ID>/processing`
- Missing per-sample reports in archive (now preserves nested directory structure)

## [2.1.3] - 2025-12-29

### Added

- Robust del_count sanitization in wf-finalize.sh to handle newlines and whitespace
- PROJECTS_DIR configuration variable for flexible archiving path
- Tag version v2.1.3 with production validation

### Fixed

- Integer expression errors in wf-finalize.sh deletion metrics (del_count containing newlines)
- Archiving path hardcoded in wf-subwf.sh (now uses PROJECTS_DIR from config)

### Changed

- wf-subwf.sh now sources nanomito.config for PROJECTS_DIR configuration
- Dynamic versioning in wf-subwf.sh via git describe

### Verified

- Complete workflow execution on Genouest HPC (v2.1.2-56-g7c56469)
- Finalization logs clean: no bash errors, HTML reports generated and emails sent
- Archiving to /projects/nanomito/<RUN_ID> successful with --delete option

## [2.1.2] - 2025-12-24

### Added

- Mobile-responsive HTML reports with adaptive CSS (@media queries)
- Dynamic parameter extraction from workflow scripts (Dorado, Baldur, Haplocheck)
- Color-coded parameter display boxes for different tools
- Complete output file tracking with validation badges
- Reports-only mode global report generation

### Changed

- Simplified metrics display in run report (deletions now shows only total count)

## [2.1.1] - 2025-12-15

### Added

- Per-sample HTML report generation
- Email notification system with HTML body

### Fixed

- Report generation and email delivery on HPC environment

## [2.1.0] - 2025-11-20

### Added

- Global HTML run report with comprehensive metrics
- Integration with email notification

## [2.0.0] - 2025-10-15

### Added

- Complete workflow orchestration with SLURM dependencies
- Modification detection (5mC, 5hmC, 6mA)
- Sample demultiplexing workflow

## [1.0.1] - 2025-09-10

### Fixed

- Minor bug fixes in basecalling workflow

## [1.0.0] - 2025-08-01

### Added

- Initial release
- GPU-accelerated basecalling with Dorado
- Basic workflow structure with SLURM integration
