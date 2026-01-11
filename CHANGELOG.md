# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.4.4] - 2026-01-11

### Added

- **Total bases metric** in SEQUENCING RUN METRICS section of HTML reports (displayed with formatted number and Gb conversion)

### Changed

- **SEQUENCING RUN METRICS display logic**: "Passed reads" and "Passed bases" metrics now hidden when values are 0 (common when basecalling is disabled in MinKNOW)

## [2.4.3] - 2026-01-11

### Changed

- **Complete English translation** of all documentation and user-facing content

### Added

- **Diagnostic tool** for sample sheet validation (`tools/diagnose_samplesheet.sh`)

## [2.4.0] - 2026-01-11

### Added

- **DEL variant enrichment in HTML reports**: Deletion variants now display as `<DEL;END=NNNNN;SVLEN=NNNN>` instead of just `<DEL>` for better clarity on deletion size
- **Haplocheck file preservation**: All haplocheck-generated files (`.raw.txt`, `.html`, etc.) now retained in `haplo/` directory

### Changed

- **Preprocessing configuration refactoring**: Removed hardcoded paths and usernames, all derived from `preprocessing.config` and script location
- **Configuration template improvements**: Updated placeholders and documentation for better clarity
- Dorado models are now configurable via `nanomito.config` (`DORADO_MODEL`, `DORADO_MODEL_COMPLEX`) instead of being hardcoded in workflows

### Fixed

- **TSV-to-HTML rendering**: Replaced problematic awk-based tab handling with Python CSV module for bulletproof field splitting
- **Report label**: Changed "Haplogroup / Status" to "Haplogroup / Contamination" for clarity
- **Haplogroup table color coding**: Contamination status values now color-coded (NO=green, YES=red, ND/other=orange)
- **Per-sample stat cards**: Labels updated to `CONTAMINATION` and `HAPLOGROUP`, with haplogroup showing `major / minor` when minor exists
- **Contamination colors in stat cards**: NO→green, YES→red, ND/other→orange (consistent with haplogroup table)
- Barcode→alias mapping in `wf-bchg.sh` now strips Windows `\r` from barcode values (CRLF sample sheets)

## [2.3.1] - 2026-01-10

### Fixed

- **Critical: Race condition in shared summary files** - Multiple parallel jobs attempting to create same summary files now properly serialized with atomic file locking (flock)
  - Affects: `haplocheck_summary.<RUN_ID>.tsv`, `demult_summary.<RUN_ID>.tsv`, `workflows_summary.<RUN_ID>.tsv`
  - Modified workflows: `wf-demultmt.sh`, `wf-modmito.sh`, `wf-bchg.sh`, `wf-subwf.sh`
  - Solves: Job failures (e.g., d58_LELM) with exit code 1 when multiple samples run in parallel
  - Implementation: Used POSIX `flock` with file descriptor 200 for mutual exclusion
  - Impact: Zero performance overhead, compatible with all HPC systems

### Changed

- Increased SLURM time limits for sample processing workflows:
  - `wf-demultmt.sh`: 4h → 6h (samples reaching 80% of previous limit)
  - `wf-modmito.sh`: 2h → 3h (preemptive increase for modification analysis)

## [2.3.0] - 2026-01-09

### Changed

**Major restructuring of haplocheck workflow for better separation of concerns:**

- **Separated VCF files**: main `.ann.vcf` (annotations only) vs `.haplo.vcf` (haplocheck-specific)
- **New directory structure**: created dedicated `haplo/` subdirectory under `processing/SAMPLE_ID/` for all haplocheck-related files
- **Clean architecture**: `.ann.vcf` now contains only MitoMap/gnomAD annotations without AF field
- **Haplocheck-specific VCF**: `.haplo.vcf` generated with PASS SNVs only + AF in FORMAT for haplocheck compatibility

### Fixed

- Removed AF injection from main `.ann.vcf` file (was causing confusion and mixing concerns)
- Updated TSV export to match new `.ann.vcf` structure (removed AF column)

### Files

- `wf-demultmt.sh`: creates `haplo/` directory, generates filtered `.haplo.vcf`, moves haplocheck outputs to `haplo/`
- `HAPLOCHECK_FIX_NOTES.md`: comprehensive documentation of new architecture
- All haplocheck files now in: `processing/SAMPLE_ID/haplo/` (`.haplo.vcf`, `-haplocheck.raw.txt`)
- Global summary remains in: `processing/haplocheck_summary.RUN_ID.tsv`

## [2.2.9] - 2026-01-08

### Added

- Troubleshooting documentation for haplocheck behavior with Nanopore VCFs in README

### Fixed

- Haplocheck heteroplasmy detection by injecting `AF` into FORMAT from `HPL`
- Haplocheck failures on structural variants by filtering to PASS SNVs only
- HTML report haplocheck table parsing (handles quotes and unexpected newlines)

### Tools

- Added `tools/rerun_all_workflows.sh` to batch re-run workflows across runs, with `--only-needing` detection

## [2.2.8] - 2026-01-02

### Security

- Removed personal configuration files from entire Git history
- Cleaned all hardcoded personal paths from scripts
- Repository now fully anonymized for public release

### Changed

- Replace /home/mferre paths with generic placeholders or $HOME variable
- Replace Windows user-specific paths with generic examples
- Documentation cleanup: removed redundant notable commits section

### Infrastructure

- Git history rewritten (force push applied)
- All tags and releases updated with clean history

## [2.2.7] - 2026-01-02

### Fixed

- CSV parsing now handles Windows CRLF line endings correctly in sample sheets
- Barcode and alias column detection failing when CSV files use Windows format
- Strip carriage return characters from CSV headers and data values
- Affects wf-bchg.sh and wf-subwf.sh workflows

## [2.2.6] - 2026-01-02

### Fixed

- Removed unused variable assignment in mitochondrial extraction subprocess call
- Suppressed unnecessary output from WSL bash command invocation

## [2.2.5] - 2025-12-31

### Fixed

- HTML report generation showing duplicate metrics across all reports
- Percentage calculations for chrM Pod5 and filtering rates computed incorrectly
- Dorado basecalling stats now parsed from last occurrence instead of first
- Total Pod5 size now calculated before computing chrM percentage
- Percentages computed before formatting numbers to strings
- Number formatting now uses non-breaking spaces for better HTML rendering
- Added warnings section to reports for missing logs or files
- Guard against null BAM size sums

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
