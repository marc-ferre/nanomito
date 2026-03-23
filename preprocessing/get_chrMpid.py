#!/usr/bin/env python3
# SPDX-License-Identifier: CECILL-2.1
# Author: Marc FERRE <marc.ferre@univ-angers.fr>
###############################################################################
# get_chrMpid.py -b bam/dir -p pod5/dir -o chrM_pids.txt
#
# Script to extract unique parent IDs (pIDs) of reads aligned to chrM from
# nanopore sequencing data. This script analyzes BAM alignment files to identify
# reads that align to the mitochondrial chromosome and retrieves their parent
# read IDs for subsequent Pod5 data filtering in the Nanomito workflow.
#
# Requires conda environment with channels and dependencies:
#    channels:
#      - anaconda
#      - conda-forge
#      - bioconda
#      - nodefaults
#    dependencies:
#      - pod5      # For reading Pod5 files
#      - pysam     # For reading BAM/SAM files
###############################################################################

# Standard library imports
import argparse  # Command line argument parsing
import os  # Operating system interface
from pathlib import Path  # Object-oriented filesystem paths
import subprocess  # For retrieving Git version info
import sys  # System-specific parameters and functions

# Third-party imports
import pysam  # Python interface to SAM/BAM files
import pod5  # Oxford Nanopore Pod5 file format library

# Script metadata
AUTHOR = "Marc FERRE <marc.ferre@univ-angers.fr>"


def parse_args():
    """
    Parse command line arguments for the script.

    Returns:
        argparse.Namespace: Parsed command line arguments containing:
            - bam: Path to BAM alignments directory
            - pod5: Path to Pod5 raw data directory
            - output: Output file path for unique parent IDs
            - dict: Path to read_id→parent_id dictionary file (optional)
                - verbose: Enable verbose output
                - debug_per_read: Emit per-read logging (very verbose)
    """
    parser = argparse.ArgumentParser(
        description="Get unique parent IDs (pIDs) of reads aligned to chrM from BAM files."
    )
    parser.add_argument(
        "-b", "--bam", type=str, required=True, help="BAM alignments directory"
    )
    parser.add_argument(
        "-p", "--pod5", type=str, required=True, help="Pod5 raw data directory"
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="chrM_pids.txt",
        help="Output file for unique parent IDs",
    )
    parser.add_argument(
        "-d",
        "--dict",
        type=str,
        default=None,
        help="TSV file mapping read_id to parent_id (read_id<TAB>parent_id). If not provided, will try to read pi:Z tags from BAM files.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose output (default: False)",
    )
    parser.add_argument(
        "--debug-per-read",
        action="store_true",
        help="Emit per-read logging (very verbose; off by default)",
    )
    return parser.parse_args()


def get_git_version() -> str:
    """Return a Git-based version string; fall back to 'unknown' if unavailable."""
    try:
        repo_root = Path(__file__).resolve().parent
        cmd = ["git", "-C", str(repo_root), "describe", "--tags", "--always", "--dirty"]
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"


def get_pod5_ids(pod5_dir: str) -> set[str]:
    """
    Extract all read IDs from Pod5 files in the specified directory.

    This function recursively scans a directory for Pod5 files and extracts
    all unique read identifiers. These IDs will be used later to verify that
    reads found in BAM files have corresponding raw data in Pod5 format.

    Args:
        pod5_dir (str): Path to directory containing Pod5 files

    Returns:
        set[str]: Set of unique read IDs found in all Pod5 files

    Raises:
        SystemExit: If the Pod5 directory does not exist (exit code 66)
    """
    pod5_path = Path(pod5_dir)
    if not pod5_path.is_dir():
        print(f"[ERROR] Pod5 dir does not exist: {pod5_dir}")
        sys.exit(66)  # EX_NOINPUT - input file/directory does not exist

    # Initialize set to store unique read IDs
    allids = set()

    # Open and read all Pod5 files recursively
    with pod5.DatasetReader(pod5_dir, recursive=True) as dataset:
        for read_record in dataset:
            # Convert read ID to string and add to set
            allids.add(str(read_record.read_id))

    print(f"[INFO] Pod5 dir: {pod5_dir} | Raw reads (Pod5) stored: {len(allids)}")
    return allids


def load_pid_dictionary(dict_file: str) -> dict[str, str]:
    """
    Load read_id to parent_id dictionary from TSV file.

    Args:
        dict_file (str): Path to TSV file with format: read_id<TAB>parent_id

    Returns:
        dict[str, str]: Dictionary mapping read_id -> parent_id

    Raises:
        SystemExit: If dictionary file does not exist or cannot be read
    """
    dict_path = Path(dict_file)
    if not dict_path.is_file():
        print(f"[ERROR] Dictionary file does not exist: {dict_file}")
        sys.exit(66)

    print(f"[INFO] Loading read_id→parent_id dictionary from: {dict_file}")

    pid_dict = {}
    with open(dict_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                print(f"[WARNING] Skipping malformed line: {line}")
                continue
            read_id, parent_id = parts
            pid_dict[read_id] = parent_id

    print(f"[INFO] Loaded {len(pid_dict)} read_id→parent_id mappings")
    return pid_dict


def get_chrM_pids(
    bam_dir: str,
    pod5_ids: set[str],
    pid_dict: dict[str, str] = None,
    verbose: bool = False,
    debug_per_read: bool = False,
) -> tuple[set[str], list[str], int, int, int, int]:
    """
    Extract unique parent IDs from BAM files for reads aligned to chrM.

    This function processes all BAM files in the specified directory to identify
    reads that align to the mitochondrial chromosome (chrM). For each aligned read,
    it extracts the parent ID using either:
    - A provided read_id→parent_id dictionary (if pid_dict is provided)
    - The 'pi:Z' tag from BAM files (if no dictionary is provided)

    Args:
        bam_dir (str): Path to directory containing BAM alignment files
        pod5_ids (set[str]): Set of available Pod5 read IDs for validation
        pid_dict (dict[str, str], optional): Dictionary mapping read_id → parent_id
        verbose (bool): Enable verbose output for detailed logging
        debug_per_read (bool): Emit per-read logging (very verbose)

    Returns:
        tuple containing:
            - set[str]: Unique parent IDs of reads aligned to chrM
            - list[str]: List of parent IDs missing from Pod5 data
            - int: Number of BAM files processed
            - int: Total number of reads aligned to chrM
            - int: Number of split reads (with pi:Z tag or from dict)
            - int: Number of duplicate reads ignored

    Raises:
        SystemExit: If the BAM directory does not exist (exit code 66)
    """
    bam_path = Path(bam_dir)
    if not bam_path.is_dir():
        print(f"[ERROR] BAM dir does not exist: {bam_dir}")
        sys.exit(66)  # EX_NOINPUT - input directory does not exist

    print(f"[INFO] Scanning BAM directory: {bam_dir}")
    
    if pid_dict:
        print(f"[INFO] Using provided read_id→parent_id dictionary ({len(pid_dict)} entries)")
    else:
        print(f"[INFO] Will extract parent IDs from pi:Z tags in BAM files")

    if verbose:
        print("[INFO] Verbose mode enabled (summary only; per-read logging requires --debug-per-read)")

    # Set to store unique parent IDs (pIDs) of reads aligned to chrM
    # For split reads, this will be the parent ID from dictionary or pi:Z tag
    # For regular reads, this will be the read ID itself
    pids = set()

    # List to store parent IDs that exist in BAM but are missing from Pod5 data
    missingids = []

    # Statistics counters
    bam_count = 0  # Number of BAM files processed
    read_chrM_count = 0  # Total reads aligned to chrM
    read_split_count = 0  # Reads with pi:Z tag (split reads)
    read_duplicate_count = 0  # Duplicate parent IDs encountered

    # Walk through all files in the BAM directory recursively
    for root, _, files in os.walk(bam_dir):
        for file in files:
            # Process only BAM files
            if file.endswith(".bam"):
                bam_count += 1
                sampath = os.path.join(root, file)
                print(f"[INFO] Processing BAM file: {sampath}")

                try:
                    # Open BAM file for reading
                    samfile = pysam.AlignmentFile(sampath, "rb")

                    # Check if the BAM file has an index and chrM reference
                    if "chrM" not in samfile.references:
                        print(
                            f"[WARNING] chrM reference not found in {sampath}, skipping file"
                        )
                        samfile.close()
                        continue

                    # Iterate through all reads aligned to chrM (mitochondrial chromosome)
                    for read in samfile.fetch("chrM"):
                        read_chrM_count += 1
                        read_id = read.query_name  # Get the read identifier
                        pid = ""  # Initialize parent ID

                        # Determine parent ID based on available data source
                        if pid_dict:
                            # Use dictionary to lookup parent ID
                            if read_id in pid_dict:
                                pid = pid_dict[read_id]
                                if pid != read_id:
                                    read_split_count += 1
                                    if debug_per_read:
                                        print(
                                            f"[INFO]    Subread ID# {read_id} was generated from Parent read pID# {pid} [FROM DICT]"
                                        )
                                else:
                                    if debug_per_read:
                                        print(f"[INFO]    Read pID# {pid} [FROM DICT]")
                            else:
                                # Read ID not in dictionary, use read_id as parent_id
                                pid = read_id
                                if debug_per_read:
                                    print(f"[WARNING] Read ID {read_id} not found in dictionary, using read_id as parent_id")
                        else:
                            # No dictionary, try to extract from pi:Z tag
                            if read.has_tag("pi:Z"):
                                read_split_count += 1
                                pid = read.get_tag("pi:Z")  # Extract parent ID from tag
                                if debug_per_read:
                                    print(
                                        f"[INFO]    Subread ID# {read_id} was generated from Parent read pID# {pid} [FROM BAM TAG]"
                                    )
                            else:
                                # No split read tag, so parent ID is the same as read ID
                                pid = read_id
                                if debug_per_read:
                                    print(f"[INFO]    Read pID# {pid}")

                        # Check if this parent ID has already been encountered (avoid duplicates)
                        if pid in pids:
                            read_duplicate_count += 1
                            if debug_per_read:
                                print(
                                    "[INFO]       Duplicate entry (not re-stored) [DUPLICATE]"
                                )
                        else:
                            # Add new unique parent ID to the set
                            pids.add(pid)  # Use add() for sets, not append()
                            if debug_per_read:
                                print("      [OK] Storing entry")

                            # Verify that the parent ID exists in the Pod5 data
                            if (
                                pid in pod5_ids
                            ):  # Use pod5_ids parameter instead of undefined allids
                                if debug_per_read:
                                    print("      [OK] pID in Pod5 raw reads")
                            else:
                                # Parent ID found in BAM but missing from Pod5 data
                                missingids.append(pid)
                                if debug_per_read:
                                    print(
                                        "      [WARNING] pID (BAM ID) missing from Pod5 IDs [MISSING]",
                                    )
                                    print("                SAM read:")
                                    print(
                                        "---------------------------------------------------"
                                    )
                                    print(read)
                                    print(
                                        "---------------------------------------------------"
                                    )

                    # Close the BAM file
                    samfile.close()

                except (OSError, ValueError, pysam.utils.SamtoolsError) as e:
                    print(f"[ERROR] Failed to process BAM file {sampath}: {e}")
                    print(f"[INFO] Continuing with remaining files...")
                    continue

    print(f"[INFO] Finished scanning all BAM files.")

    # Return all collected data as a tuple
    return (
        pids,  # Set of unique parent IDs
        missingids,  # List of IDs missing from Pod5 data
        bam_count,  # Number of BAM files processed
        read_chrM_count,  # Total reads aligned to chrM
        read_split_count,  # Number of split reads
        read_duplicate_count,  # Number of duplicate reads ignored
    )


def write_ids(ids: set[str], output_file: str) -> None:
    """
    Write unique parent IDs to output file.

    This function takes a set of unique parent IDs and writes them to a text file,
    one ID per line. This file will be used by subsequent tools to filter Pod5 data.

    Args:
        ids (set[str]): Set of unique parent IDs to write
        output_file (str): Path to output file
    """
    with open(output_file, "w") as f:
        for pid in ids:
            f.write(f"{pid}\n")
    print(
        f"[OK] {len(ids)} unique Pod5 IDs of reads aligned to chrM written in file: {output_file}"
    )


def main():
    """
    Main function that orchestrates the entire workflow.

    This function:
    1. Displays script information
    2. Parses command line arguments
    3. Validates input directories
    4. Extracts all Pod5 read IDs from the specified directory
    5. Processes BAM files to find reads aligned to chrM and their parent IDs
    6. Displays comprehensive statistics about the processing
    7. Writes the unique parent IDs to the output file
    """
    print(f"Script: get_chrMpid.py v.{get_git_version()} by {AUTHOR}")

    # Parse command line arguments
    args = parse_args()

    # Validate input directories exist
    if not Path(args.bam).is_dir():
        print(f"[ERROR] BAM directory does not exist: {args.bam}")
        sys.exit(66)

    if not Path(args.pod5).is_dir():
        print(f"[ERROR] Pod5 directory does not exist: {args.pod5}")
        sys.exit(66)

    # Check if output directory exists, create if necessary
    output_dir = Path(args.output).parent
    if not output_dir.exists():
        try:
            output_dir.mkdir(parents=True, exist_ok=True)
            print(f"[INFO] Created output directory: {output_dir}")
        except PermissionError:
            print(f"[ERROR] Cannot create output directory: {output_dir}")
            sys.exit(77)  # EX_NOPERM

    # Extract all Pod5 read IDs for validation
    pod5_ids = get_pod5_ids(args.pod5)

    # Load read_id→parent_id dictionary if provided
    pid_dict = None
    if args.dict:
        pid_dict = load_pid_dictionary(args.dict)

    # Process BAM files to find chrM-aligned reads and their parent IDs
    (
        pids,  # Unique parent IDs
        missingids,  # IDs missing from Pod5 data
        bam_count,  # Number of BAM files processed
        read_chrM_count,  # Total reads aligned to chrM
        read_split_count,  # Split reads count
        read_duplicate_count,  # Duplicate reads ignored
    ) = get_chrM_pids(
        args.bam,
        pod5_ids,
        pid_dict,
        args.verbose,
        args.debug_per_read,
    )

    # Display comprehensive processing statistics
    print("\n" + "=" * 50)
    print("PROCESSING SUMMARY:")
    print("=" * 50)
    print("| Pod5 reads:", len(pod5_ids))
    print("| BAM files processed:", bam_count)
    print("| Reads aligned to chrM:", read_chrM_count)
    print("|   Split reads:", read_split_count)
    print("|   Duplicate reads ignored:", read_duplicate_count)
    print("|   Unique reads pIDs:", len(pids))
    print("|   Missing reads pIDs:", len(missingids))

    # Display missing IDs if any were found
    if missingids:
        print("\nMissing IDs:", missingids)

    # Write unique parent IDs to output file
    write_ids(pids, args.output)


# Entry point for script execution
if __name__ == "__main__":
    main()
