# Integration Notes - wf-subwf.sh → submit_nanomito.sh

**Date:** 26 octobre 2025  
**Commit:** c5297a1

## Summary

Successfully merged the functionality of `wf-subwf.sh` into `submit_nanomito.sh`, eliminating the need for an intermediate SLURM job orchestrator. This simplifies the architecture and reduces job overhead.

## Changes Made

### 1. **submit_nanomito.sh** - Major Refactoring

#### New Features
- **`--skip-bchg` option**: Skip basecalling/demux and only submit analysis workflows
- **Direct job submission**: Now directly submits demultmt and modmito jobs for each sample
- **Conflict detection**: Prevents using `--bchg-only` and `--skip-bchg` together

#### Architecture Changes
- Removed dependency on `WF_SUBWF`
- Added `WF_DEMULTMT` and `WF_MODMITO` workflow paths
- Integrated sample directory discovery from `wf-subwf.sh`
- Integrated job submission loop for per-sample workflows
- Proper dependency management:
  - If bchg job submitted: demultmt depends on bchg
  - modmito always depends on demultmt

#### Code Structure
```bash
# Old architecture (2 jobs + N*2 analysis jobs)
submit_nanomito.sh → wf-bchg.sh (Job 1)
                  → wf-subwf.sh (Job 2) → demultmt jobs
                                        → modmito jobs

# New architecture (1 job + N*2 analysis jobs)
submit_nanomito.sh → wf-bchg.sh (Job 1)
                  → demultmt jobs (directly)
                  → modmito jobs (directly)
```

### 2. **README.md** - Documentation Update

- Updated workflow architecture diagram
- Removed `wf-subwf.sh` from workflow descriptions
- Added usage examples for new options
- Renumbered workflow sections (5 workflows instead of 6)
- Added sample sheet alias mapping feature description

## Testing Plan

### Test 1: Complete Pipeline (Default Mode)
```bash
~/workflows/submit_nanomito.sh /scratch/mferre/workbench/250916_MK1B_RUN15/
```

**Expected Behavior:**
- Submit 1 bchg job
- Submit 4 demultmt jobs (one per sample, depends on bchg)
- Submit 4 modmito jobs (one per sample, depends on demultmt)
- Total: 9 jobs

### Test 2: Basecalling Only
```bash
~/workflows/submit_nanomito.sh --bchg-only /scratch/mferre/workbench/250916_MK1B_RUN15/
```

**Expected Behavior:**
- Submit 1 bchg job only
- Skip analysis workflows
- Total: 1 job

### Test 3: Analysis Only (Skip Basecalling)
```bash
~/workflows/submit_nanomito.sh --skip-bchg /scratch/mferre/workbench/250916_MK1B_RUN15/
```

**Expected Behavior:**
- Skip bchg job
- Submit 4 demultmt jobs (no dependency on bchg)
- Submit 4 modmito jobs (depends on demultmt)
- Total: 8 jobs

### Test 4: Conflict Detection
```bash
~/workflows/submit_nanomito.sh --bchg-only --skip-bchg /path/to/run/
```

**Expected Behavior:**
- Exit with error code 128
- Error message: "Cannot use --bchg-only and --skip-bchg together"

## Validation Checklist

- [x] Code syntax validated (`bash -n`)
- [x] Shellcheck passed (no warnings)
- [x] Git commits created and pushed
- [x] README.md updated
- [ ] Test 1 (complete pipeline) executed on Genouest
- [ ] Test 2 (--bchg-only) executed on Genouest
- [ ] Test 3 (--skip-bchg) executed on Genouest
- [ ] Test 4 (conflict detection) verified
- [ ] Log files verified in processing/ directories
- [ ] Job dependencies validated with `squeue --dependency`

## Migration Notes

### For Existing Workflows
- `wf-subwf.sh` is now **deprecated** but still functional
- New submissions should use `submit_nanomito.sh` directly
- Old scripts in queue will continue to work

### Cleanup Tasks
- [ ] Update ~/workflows/ on Genouest with `git pull`
- [ ] Consider archiving `wf-subwf.sh` to Archive/ directory
- [ ] Update any documentation or scripts referencing `wf-subwf.sh`

## Benefits

1. **Reduced Job Count**: Eliminates 1 intermediate orchestrator job
2. **Simpler Architecture**: Direct submission from main script
3. **Better Control**: `--skip-bchg` allows re-running analysis on existing FASTQ
4. **Clearer Dependencies**: Explicit job dependency management
5. **Easier Debugging**: All submission logic in one place

## Known Issues

None at this time.

## Next Steps

1. Pull latest changes on Genouest HPC
2. Execute Test 1 with complete pipeline
3. Validate job dependencies and log file organization
4. Consider archiving `wf-subwf.sh` once testing is complete
