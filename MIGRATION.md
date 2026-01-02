# Migration Notice - v2.2.8

## ⚠️ Important: Git History Rewritten

As of **January 2, 2026** (v2.2.8), the Git history of this repository has been rewritten to remove sensitive personal information and configuration files.

## Why This Change?

For security and privacy reasons, we removed:
- Personal configuration files (`nanomito.config`, `preprocessing/preprocessing.config`)
- Hardcoded personal paths and usernames
- Institutional server information

## What You Need to Do

If you have an existing clone of this repository, you **must** take action:

### Option 1: Fresh Clone (Recommended)

The simplest approach is to clone the repository again:

```bash
# 1. Backup any local changes you have
cd /path/to/your/nanomito
git stash  # or commit your changes

# 2. Move to parent directory and delete old clone
cd ..
mv nanomito nanomito.old

# 3. Clone fresh copy
git clone git@github.com:marc-ferre/nanomito.git
cd nanomito

# 4. Restore your configuration files
cp ../nanomito.old/nanomito.config ./
cp ../nanomito.old/preprocessing/preprocessing.config preprocessing/

# 5. Verify everything works, then delete old clone
rm -rf ../nanomito.old
```

### Option 2: Hard Reset (Advanced Users)

If you prefer to update your existing clone:

```bash
# 1. Backup your configuration files (they will be deleted!)
cp nanomito.config ~/nanomito.config.backup
cp preprocessing/preprocessing.config ~/preprocessing.config.backup

# 2. Fetch the new history
git fetch origin

# 3. Hard reset to match remote (⚠️ destroys local changes)
git reset --hard origin/main

# 4. Force update all tags
git fetch --tags --force

# 5. Restore your configuration files
cp ~/nanomito.config.backup nanomito.config
cp ~/preprocessing.config.backup preprocessing/preprocessing.config

# 6. Clean up
rm ~/nanomito.config.backup ~/preprocessing.config.backup
```

### Option 3: Only Pulling New Changes Won't Work

❌ **This will fail:**

```bash
git pull  # ERROR: divergent histories
```

The histories are now incompatible. You must use Option 1 or 2.

## What Changed in v2.2.8?

- **Security**: All personal information removed from Git history
- **Configuration**: Template files (`.template`) are now the only versioned configs
- **Paths**: Generic placeholders replace hardcoded paths
- **Tags**: All releases updated with clean history

## Verify Your Update

After migrating, verify you have the clean version:

```bash
# Should show v2.2.8 or later
git describe --tags

# These files should NOT exist in Git (but can exist locally)
git ls-files | grep -E '(nanomito\.config$|preprocessing\.config$)'
# Should return nothing

# Check you have the templates
ls -la *.template preprocessing/*.template
# Should show:
# nanomito.config.template
# preprocessing/preprocessing.config.template
```

## Need Help?

If you encounter issues:
1. Check the [README](README.md) for setup instructions
2. Review the [CHANGELOG](CHANGELOG.md) for v2.2.8 details
3. Open an issue on GitHub

## Timeline

- **Before 2026-01-02**: Old history with personal information
- **After 2026-01-02**: Clean history, v2.2.8+

---

**Note:** Your local configuration files (`nanomito.config`, `preprocessing/preprocessing.config`) are safe and **should not be committed to Git**. They are in `.gitignore`.
