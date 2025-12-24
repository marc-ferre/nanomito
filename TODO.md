# TODO List - Nanomito

Last updated: 2025-12-24

## ✅ Recently Completed (v2.1.1 - 2025-12-24)

### HTML Report Enhancements - Responsive Design & Parameter Tracking

- [x] **Mobile-responsive HTML reports with adaptive CSS** ✅ COMPLETED
  - ✅ Added @media queries for tablets (max-width: 768px) and mobile (max-width: 480px)
  - ✅ Responsive grid layout with auto-fit columns (140px minimum on tablet, single column on mobile)
  - ✅ Adaptive font sizes: h1 reduced to 18px on tablet, 16px on mobile
  - ✅ Stat values reduced to 16px on tablet, 9px on mobile
  - ✅ Table horizontal scrolling with overflow-x: auto for mobile viewing
  - ✅ Verified on iPhone and tablet devices in test environment

- [x] **Dynamic parameter extraction from workflow scripts** ✅ COMPLETED
  - ✅ Dorado basecaller parameters extracted from wf-bchg.sh using AWK pattern matching
  - ✅ Baldur demultiplexing parameters extracted from wf-demultmt.sh
  - ✅ Haplocheck quality metrics parameters extracted from wf-demultmt.sh
  - ✅ No more hardcoded parameters - all extracted dynamically from source scripts
  - ✅ Improved maintainability: updating workflow parameters automatically reflects in reports

- [x] **Color-coded parameter display boxes** ✅ COMPLETED
  - ✅ Dorado parameters with blue left border (#3498db)
  - ✅ Baldur parameters with green left border (#27ae60)
  - ✅ Haplocheck parameters with purple left border (#9b59b6)
  - ✅ Consistent styling: background #f8f9fa, padding 10px, margin 10px 0, monospace font 11px
  - ✅ Visual differentiation for quick tool identification

- [x] **Simplified metrics display for run report** ✅ COMPLETED
  - ✅ Deletions section now shows only total count instead of full data table
  - ✅ Uses metric-row div structure with label-left/value-right layout (flexbox justify-content: space-between)
  - ✅ Consistent formatting with Variants and other metrics sections
  - ✅ Reduced visual clutter in run report while maintaining essential information

- [x] **Complete output file tracking in reports** ✅ COMPLETED
  - ✅ Sample HTML report filenames added to Output files section in per-sample reports
  - ✅ Sample HTML report filenames added to Output files section in global run report
  - ✅ File size display for each report file
  - ✅ Validation badges (✓ for existing files, ✗ for missing)
  - ✅ Report files appear first in Output files list (before BAM/VCF/TSV files)

- [x] **Reports-only mode global report generation** ✅ COMPLETED
  - ✅ Fixed: Global run report was empty when using `--reports-only` flag
  - ✅ Removed early `exit 0` after sample report loop
  - ✅ Workflow now continues to generate full global run report in reports-only mode
  - ✅ Email notification still sent correctly with complete report

- [x] **Comprehensive testing on production HPC** ✅ COMPLETED
  - ✅ Tested with real 250916_MK1B_RUN15 run (3 samples: DURM, BARF, BREA)
  - ✅ Sample reports: 24K each, generated in 3-5 seconds per sample
  - ✅ Global run report: 15K, 465+ lines, generated in ~9 seconds
  - ✅ Parameter extraction verified for all three tools
  - ✅ Mobile responsive design verified on simulated iPhone viewport
  - ✅ File tracking and badges verified in both sample and global reports
  - ✅ Email notifications sent successfully to [marc.ferre@univ-angers.fr](mailto:marc.ferre@univ-angers.fr)

## ✅ Recently Completed (v2.0.0 - 2025-11-04)

### Archiving & Email Reporting

- [x] **Integrated archiving workflow** ✅ COMPLETED
  - ✅ Added `wf-archiving.sh` with automatic dependency management
  - ✅ Fixed critical job dependency bug (archiving/finalize now wait for all sample jobs)
  - ✅ Added `--archiving-only` and `--skip-archiving` options
  - ✅ `wf-subwf.sh` now handles archiving/finalize submission with proper dependencies
  - ✅ Archiving summary with human-readable sizes and duration metrics

- [x] **HTML email reports with responsive design** ✅ COMPLETED
  - ✅ Beautiful responsive HTML email optimized for mobile (iPhone, Android)
  - ✅ Color-coded status indicators (success/warning/error)
  - ✅ Per-sample results with alignment stats, haplogroups, variants, file sizes
  - ✅ Deletions table from Baldur analysis for each sample
  - ✅ Archiving summary section with destination, size, duration
  - ✅ Fixed total runtime calculation (was showing 00:00:00)
  - ✅ English number formatting (331,496 and 3.7G instead of French format)
  - ✅ Uniform time formatting (HH:MM:SS with two digits)
  - ✅ Removed double slashes in error log file paths

- [x] **Email notification optimization** ✅ COMPLETED
  - ✅ Removed `END` from `MAIL_TYPE` variables to prevent success email spam
  - ✅ SLURM emails now sent only on failures
  - ✅ Success notifications handled exclusively by `wf-finalize.sh` HTML email

- [x] **Version management** ✅ COMPLETED
  - ✅ Updated all workflow scripts to VERSION='2.0.0'
  - ✅ Updated README.md with comprehensive v2.0.0 changelog
  - ✅ Created and pushed v2.0.0 git tag
  - ✅ Published v2.0.0 release on GitHub

## 🔴 High Priority

### Configuration Management

- [x] **Create centralized configuration file for all workflow parameters** ✅ COMPLETED 2025-11-03
  - ✅ Created `nanomito.config` with all hardcoded paths and variables
  - ✅ Used shell-sourceable format for easy integration
  - ✅ Included: reference paths, conda environments, binary locations, workflow scripts
  - ✅ Updated all 5 workflows to source the config file
  - ✅ Fixed path resolution for both direct execution and sbatch contexts
  - ✅ Documented in README.md with Configuration section

- [x] **Create preprocessing configuration files** ✅ COMPLETED 2025-11-04
  - ✅ Created `preprocessing/preprocessing.config` for Bash scripts (Linux/WSL/HPC)
  - ✅ Created `preprocessing/preprocessing.ps1` for PowerShell scripts (Windows)
  - ✅ Extracted all hardcoded paths and settings
  - ✅ Variables: conda, Python scripts, Dorado, references, Genouest settings
  - ✅ Added `preprocessing/README.md` with usage documentation
  - ✅ Updated all scripts to source config files (wf-getmt.sh, wf-uplgo.sh, wf-prebchg.ps1, submit_preprocessing.ps1)
  - ✅ Renamed scripts to wf-* convention for consistency
  - ✅ Simplified SSH authentication (single passphrase prompt, no redundant confirmations)

- [x] **Enhance submit_nanomito.sh to replace wf-subwf.sh functionality** ✅ COMPLETED 2025-10-27
  - ✅ Integrated sample detection logic directly into submit_nanomito.sh
  - ✅ Auto-detect samples in fastq_pass/ directory
  - ✅ Submit demultmt and modmito jobs for each detected sample
  - ✅ Maintain job dependency management
  - ✅ Add option to process specific samples only (--skip-bchg)
  - ✅ Deprecated wf-subwf.sh (moved to Archive/)
  - ✅ Updated documentation and usage examples

### Testing & Validation

- [ ] Add unit tests for `preprocessing/create_pid_dict.py`
  - Test with corrupted BAM files
  - Test with missing pi:Z tags
  - Test with empty BAM files
  - Validate TSV output format

- [ ] Add integration tests for `preprocessing/get_chrMpid.py`
  - Test with dictionary file (`-d` parameter)
  - Test without dictionary (fallback to pi:Z tags)
  - Test error handling for missing files

- [ ] Validate `wf-demultmt.sh` with real production data
  - Test all 7 steps complete successfully
  - Verify Pod5 filtering works with pid_dict.tsv
  - Check memory usage doesn't exceed 150GB

### Error Handling

- [ ] Add validation for corrupted `pid_dict.tsv` files
  - Check TSV format (two columns)
  - Verify no duplicate read_ids
  - Handle truncated files gracefully

- [ ] Improve error messages in `wf-demultmt.sh`
  - Add specific error codes for different failures
  - Include troubleshooting hints in error messages
  - Log full command that failed

- [ ] Add retry logic for network-dependent operations
  - Conda environment activation
  - File I/O operations on shared storage

### Bug Reports

- [ ] **Report Dorado/Pod5 bug requiring --missing-ok flag**
  - Issue: Pod5 filter fails without --missing-ok even when all read_ids exist
  - Context: Occurs in wf-demultmt.sh when filtering Pod5 files with pid_dict.tsv
  - Workaround: Currently using --missing-ok --duplicate-ok flags
  - Action: Submit bug report to Dorado/Pod5 repositories on GitHub
  - Version info: Dorado 0.8.3, Pod5 tools (check version)
  - Include: Sample data, command line, error message, expected vs actual behavior

## 🟡 Medium Priority

### Performance Optimization

- [ ] Profile memory usage in `wf-demultmt.sh`
  - Identify peak memory consumption points
  - Optimize large file processing
  - Consider streaming approach for large TSV files

- [ ] Optimize `create_pid_dict.py` for large BAM files
  - Add progress reporting
  - Consider parallel processing with multiprocessing
  - Add option to process BAM files incrementally

- [ ] Add parallel processing to `wf-getmt.sh`
  - Process multiple BAM files concurrently
  - Use GNU parallel for Pod5 filtering

### User Experience

- [x] **Improve final workflow email report readability** ✅ COMPLETED 2025-11-04
  - ✅ Synthesized and summarized log content instead of raw tails
  - ✅ Added structured sections: Workflow Summary, Sequencing Metrics, Per-Sample Results, Summary Files, Archiving Summary
  - ✅ Converted to HTML format with responsive design
  - ✅ Mobile-optimized for iPhone/Android viewing
  - ✅ Color-coded status indicators and badges
  - ✅ Detailed per-sample metrics and file status
  - ✅ Highlighted important metrics (haplogroups, variant counts, alignment stats, runtimes)
  - ✅ Reduced verbosity while keeping essential information
  - ✅ Added visual structure with box drawing characters and icons
  - ✅ Included status indicators (✓/✗) for key output files
  - ✅ Added error detection in sample logs
  - 📋 Future: Consider HTML format for even better formatting

- [ ] **Add option to process 'unclassified' folder**
  - Add command-line option (e.g., --include-unclassified) to submit_nanomito.sh
  - By default, skip the 'unclassified' folder in fastq_pass/
  - When enabled, process unclassified samples like regular samples
  - Update wf-subwf.sh sample discovery logic

- [ ] Add progress bars to long-running operations
  - Use `tqdm` in Python scripts
  - Add time estimates in bash scripts
  - Show percentage completion

- [ ] Create configuration file for workflow parameters
  - YAML or JSON config file
  - Reduce hardcoded paths
  - Make it easier to switch between environments

- [ ] Add dry-run mode to workflows
  - Preview what will be executed
  - Validate inputs without running

### Documentation

- [ ] Create detailed tutorial with example data
  - Step-by-step guide from raw data to results
  - Include expected outputs at each step
  - Add troubleshooting for common errors

- [ ] Add architecture diagrams
  - Data flow diagram
  - File dependency graph
  - Processing timeline visualization

- [ ] Document conda environment setup
  - List exact package versions
  - Provide environment.yml files
  - Add installation troubleshooting

## 🟢 Low Priority

### Code Quality

- [ ] Refactor logging functions into separate module
  - Create `lib/logging.sh` with all log functions
  - Source in all workflows
  - Add log levels (DEBUG, INFO, WARN, ERROR)

- [ ] Add color output to console logs
  - Use ANSI colors for different log levels
  - Make it optional (disable for log files)
  - Follow standard color conventions

- [ ] Improve code documentation
  - Add docstrings to all Python functions
  - Add function headers in bash scripts
  - Document complex logic sections

### Features

- [ ] Add support for multiple reference genomes
  - Allow custom reference paths
  - Support different organisms
  - Auto-detect genome version

- [ ] Implement checkpointing in workflows
  - Save state at each step
  - Allow resume from last successful step
  - Skip already completed steps

- [ ] Create summary report generator
  - Aggregate statistics from all samples
  - Generate HTML report
  - Include quality metrics and plots

### Development & DevOps

- [ ] Create Docker container for local testing
  - Include all dependencies
  - Mount volumes for data
  - Document usage

- [ ] Add pre-commit hooks
  - Run shellcheck automatically
  - Check Python syntax with flake8
  - Validate markdown with markdownlint

- [ ] Set up continuous integration (GitHub Actions)
  - Run shellcheck on all scripts
  - Run Python tests
  - Validate documentation

### Monitoring & Debugging

- [ ] Add detailed timing information
  - Log start/end time for each operation
  - Calculate and display duration
  - Identify bottlenecks

- [ ] Create debug mode
  - Set with environment variable: `DEBUG=1`
  - Show all executed commands (set -x)
  - Keep all intermediate files

- [ ] Add resource usage reporting
  - Track CPU, memory, disk usage
  - Log to monitoring file
  - Generate usage statistics

## 📋 Future Enhancements

### Advanced Features

- [ ] Support for multi-sample comparison
  - Compare variants across samples
  - Identify common/unique variants
  - Generate comparison matrix

- [ ] Add quality filtering options
  - Filter by read quality score
  - Filter by alignment quality
  - Filter by coverage depth

- [ ] Implement automatic cleanup
  - Remove intermediate files after successful completion
  - Compress old log files
  - Archive completed runs

### Integration

- [ ] Add support for other basecallers
  - Guppy compatibility
  - MinKNOW integration
  - Support legacy formats

- [ ] Create web dashboard
  - Monitor running jobs
  - View real-time logs
  - Display summary statistics

- [ ] Add email notifications
  - Notify on job completion
  - Alert on failures
  - Send summary reports

## ✅ Completed (Archive)

### v25.11.04 - Feature Enhancements

- [x] Added `--include-unclassified` option to submit_nanomito.sh
- [x] Created preprocessing configuration files (preprocessing.config and preprocessing.ps1)
- [x] Added preprocessing/README.md documentation
- [x] Fixed help message column alignment in submit_nanomito.sh

### v25.11.03 - Configuration Centralization

- [x] Created `nanomito.config` with all workflow configuration variables
- [x] Fixed path resolution for relative paths (e.g., `nanomito/script.sh`)
- [x] Fixed path resolution for sbatch execution using `NANOMITO_DIR` env var
- [x] Updated all 5 workflows: submit_nanomito.sh, wf-bchg.sh, wf-demultmt.sh, wf-modmito.sh, wf-subwf.sh
- [x] Added comprehensive documentation in README.md
- [x] Tested on Genouest cluster with production data

### v25.10.27 - Workflow Improvements

- [x] Create PID dictionary during preprocessing
- [x] Fix SIGPIPE errors in wf-demultmt.sh
- [x] Add support for dictionary file in get_chrMpid.py
- [x] Update README with preprocessing workflow
- [x] Fix cut.txt parsing (read 3rd column correctly)
- [x] Add error handling for missing pid_dict.tsv
- [x] Improve helper functions (silent mode)
- [x] Add shellcheck compliance
- [x] Add .gitignore for **pycache**

### v25.10.27 - Submit Script Enhancement

- [x] Integrated sample detection logic directly into submit_nanomito.sh
- [x] Auto-detect samples in fastq_pass/ directory
- [x] Submit demultmt and modmito jobs for each detected sample
- [x] Maintain job dependency management
- [x] Add option to process specific samples only (--skip-bchg)
- [x] Deprecated wf-subwf.sh (moved to Archive/)
- [x] Updated documentation and usage examples

## 📝 Notes

### Known Issues

- ✅ SOLVED: SLURM path resolution with `${BASH_SOURCE[0]}` - now using `NANOMITO_DIR` env var
- Some conda environments may conflict - document compatible versions
- Large Pod5 files (>10GB) may require increased memory allocation

### Performance Benchmarks

To be added after testing with production data:

- Average runtime per step
- Memory usage per sample size
- Disk space requirements

### Dependencies to Monitor

- Dorado updates (basecaller model changes)
- pod5 library version compatibility
- samtools/minimap2 updates

---

**How to use this TODO list:**

1. **Pick a task**: Choose from High Priority first
2. **Create a branch**: `git checkout -b feature/task-name`
3. **Make changes**: Implement the feature or fix
4. **Test**: Validate on test data first
5. **Update this file**: Move task to "Completed" section
6. **Submit PR**: Request review before merging

**Labels for commits:**

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation
- `refactor:` Code refactoring
- `test:` Adding tests
- `chore:` Maintenance tasks
