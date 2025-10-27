# TODO List - Nanomito

Last updated: 2025-10-27

## 🔴 High Priority

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

## ✅ Completed (v25.10.27)

- [x] Create PID dictionary during preprocessing
- [x] Fix SIGPIPE errors in wf-demultmt.sh
- [x] Add support for dictionary file in get_chrMpid.py
- [x] Update README with preprocessing workflow
- [x] Fix cut.txt parsing (read 3rd column correctly)
- [x] Add error handling for missing pid_dict.tsv
- [x] Improve helper functions (silent mode)
- [x] Add shellcheck compliance
- [x] Add .gitignore for __pycache__

## 📝 Notes

### Known Issues

- SLURM path resolution with `${BASH_SOURCE[0]}` requires absolute paths
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
