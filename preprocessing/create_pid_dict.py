#!/usr/bin/env python3
"""create_pid_dict.py

Create a TSV file mapping read_id -> parent_id from BAM files (Dorado outputs).

Usage: create_pid_dict.py -b /path/to/bam_dir -o /path/to/output_dict.tsv
"""
import argparse
from pathlib import Path
import subprocess
import sys
import os
try:
    import pysam
except Exception as e:
    print(f"[ERROR] pysam is required: {e}")
    sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description="Create read_id->parent_id dictionary from BAMs")
    p.add_argument("-b", "--bam", required=True, help="BAM directory")
    p.add_argument("-o", "--output", required=True, help="Output TSV file")
    return p.parse_args()


def main():
    args = parse_args()
    bam_dir = Path(args.bam)
    out_file = Path(args.output)

    if not bam_dir.is_dir():
        print(f"[ERROR] BAM directory does not exist: {bam_dir}")
        sys.exit(66)

    out_file.parent.mkdir(parents=True, exist_ok=True)

    # Map to store read_id -> parent_id
    mapping = {}

    for root, _, files in os.walk(bam_dir):
        for fn in files:
            if not fn.endswith('.bam'):
                continue
            bam_path = os.path.join(root, fn)
            print(f"[INFO] Scanning BAM: {bam_path}")
            try:
                with pysam.AlignmentFile(bam_path, "rb") as bf:
                    for read in bf.fetch(until_eof=True):
                        rid = read.query_name
                        pid = None
                        # Try common tag names
                        try:
                            if read.has_tag('pi:Z'):
                                pid = read.get_tag('pi:Z')
                            elif read.has_tag('pi'):
                                pid = read.get_tag('pi')
                        except Exception:
                            # ignore tag errors
                            pid = None

                        if pid is None:
                            pid = rid

                        mapping[rid] = pid
            except Exception as e:
                print(f"[WARNING] Failed to process {bam_path}: {e}")
                continue

    # Write TSV
    with out_file.open('w') as fo:
        for rid, pid in mapping.items():
            fo.write(f"{rid}\t{pid}\n")

    print(f"[OK] Wrote {len(mapping)} mappings to {out_file}")


if __name__ == '__main__':
    print(f"Script: create_pid_dict.py v.{get_git_version()} by {AUTHOR}")
    main()
#!/usr/bin/env python3
###############################################################################
# create_pid_dict.py - Create read_id to parent_id dictionary from BAM files
#
# This script extracts read IDs and their parent IDs from BAM files generated
# by Dorado basecaller. The parent ID information is stored in the 'pi:Z' tag
# for split reads. This dictionary will be used later in the Nanomito workflow
# to map reads back to their parent reads without relying on BAM tags.
#
# Output format: TSV file with two columns (no header)
#   read_id<TAB>parent_id
#
# For split reads: read_id != parent_id (parent_id from pi:Z tag)
# For regular reads: read_id == parent_id (no pi:Z tag)
###############################################################################

import argparse
import os
import sys
from pathlib import Path

import pysam

AUTHOR = "Marc FERRE <marc.ferre@univ-angers.fr>"


def get_git_version() -> str:
    """Return a Git-based version string; fall back to 'unknown' if unavailable."""
    try:
        repo_root = Path(__file__).resolve().parent
        cmd = ["git", "-C", str(repo_root), "describe", "--tags", "--always", "--dirty"]
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Create read_id to parent_id dictionary from BAM files."
    )
    parser.add_argument(
        "-b", "--bam", type=str, required=True, help="BAM directory"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        required=True,
        help="Output TSV file (read_id<TAB>parent_id)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Enable verbose output"
    )
    return parser.parse_args()


def create_pid_dictionary(bam_dir: str, verbose: bool = False) -> dict[str, str]:
    """
    Create dictionary mapping read_id to parent_id from BAM files.
    
    Args:
        bam_dir: Path to directory containing BAM files
        verbose: Enable verbose output
        
    Returns:
        Dictionary mapping read_id -> parent_id
    """
    bam_path = Path(bam_dir)
    if not bam_path.is_dir():
        print(f"[ERROR] BAM directory does not exist: {bam_dir}")
        sys.exit(66)
    
    print(f"[INFO] Scanning BAM directory: {bam_dir}")
    
    pid_dict = {}
    bam_count = 0
    read_count = 0
    split_count = 0
    
    # Walk through BAM directory
    for root, _, files in os.walk(bam_dir):
        for file in files:
            if file.endswith(".bam"):
                bam_count += 1
                bam_path = os.path.join(root, file)
                print(f"[INFO] Processing BAM file: {bam_path}")
                
                try:
                    samfile = pysam.AlignmentFile(bam_path, "rb")
                    
                    for read in samfile:
                        read_count += 1
                        read_id = read.query_name
                        
                        # Check for parent ID tag (pi:Z) indicating split read
                        if read.has_tag("pi:Z"):
                            parent_id = read.get_tag("pi:Z")
                            split_count += 1
                            if verbose:
                                print(f"[INFO]   Split read: {read_id} -> {parent_id}")
                        else:
                            # No split, parent_id is same as read_id
                            parent_id = read_id
                            if verbose:
                                print(f"[INFO]   Regular read: {read_id}")
                        
                        # Store in dictionary
                        pid_dict[read_id] = parent_id
                    
                    samfile.close()
                    
                except (OSError, ValueError, pysam.utils.SamtoolsError) as e:
                    print(f"[ERROR] Failed to process BAM file {bam_path}: {e}")
                    continue
    
    print(f"\n[INFO] Processing complete:")
    print(f"[INFO]   BAM files: {bam_count}")
    print(f"[INFO]   Total reads: {read_count}")
    print(f"[INFO]   Split reads: {split_count}")
    print(f"[INFO]   Dictionary entries: {len(pid_dict)}")
    
    return pid_dict


def write_dictionary(pid_dict: dict[str, str], output_file: str) -> None:
    """
    Write read_id to parent_id dictionary to TSV file.
    
    Args:
        pid_dict: Dictionary mapping read_id -> parent_id
        output_file: Output file path
    """
    with open(output_file, "w") as f:
        for read_id, parent_id in pid_dict.items():
            f.write(f"{read_id}\t{parent_id}\n")
    
    print(f"[OK] Dictionary written to: {output_file}")
    print(f"[OK] Total entries: {len(pid_dict)}")


def main():
    """Main function."""
    print(f"Script: create_pid_dict.py v.{VERSION} by {AUTHOR}")
    
    args = parse_args()
    
    # Validate BAM directory
    if not Path(args.bam).is_dir():
        print(f"[ERROR] BAM directory does not exist: {args.bam}")
        sys.exit(66)
    
    # Create output directory if needed
    output_dir = Path(args.output).parent
    if not output_dir.exists():
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            print(f"[INFO] Created output directory: {output_dir}")
        except PermissionError:
            print(f"[ERROR] Cannot create output directory: {output_dir}")
            sys.exit(77)
    
    # Create dictionary
    pid_dict = create_pid_dictionary(args.bam, args.verbose)
    
    # Write to file
    write_dictionary(pid_dict, args.output)


if __name__ == "__main__":
    main()
