#!/usr/bin/env python3
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
import sys  # System-specific parameters and functions

# Third-party imports
import pysam  # Python interface to SAM/BAM files
import pod5  # Oxford Nanopore Pod5 file format library

# Script metadata
VERSION = "25.08.26.1"
AUTHOR = "Marc FERRE <marc.ferre@univ-angers.fr>"


def parse_args():
    """
    Parse command line arguments for the script.

    Returns:
        argparse.Namespace: Parsed command line arguments containing:
            - bam: Path to BAM alignments directory
            - pod5: Path to Pod5 raw data directory
            - output: Output file path for unique parent IDs
            - verbose: Enable verbose output
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
        "-v",
        "--verbose",
        action="store_true",
        help="Enable verbose output (default: False)",
    )
    return parser.parse_args()


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


def get_chrM_pids(
    bam_dir: str, pod5_ids: set[str], verbose: bool = False
) -> tuple[set[str], list[str], int, int, int, int]:
    """
    Extract unique parent IDs from BAM files for reads aligned to chrM.

    This function processes all BAM files in the specified directory to identify
    reads that align to the mitochondrial chromosome (chrM). For each aligned read,
    it extracts the parent ID, which is either the read ID itself or the parent ID
    from the 'pi:Z' tag for split reads.

    Args:
        bam_dir (str): Path to directory containing BAM alignment files
        pod5_ids (set[str]): Set of available Pod5 read IDs for validation
        verbose (bool): Enable verbose output for detailed logging

    Returns:
        tuple containing:
            - set[str]: Unique parent IDs of reads aligned to chrM
            - list[str]: List of parent IDs missing from Pod5 data
            - int: Number of BAM files processed
            - int: Total number of reads aligned to chrM
            - int: Number of split reads (with pi:Z tag)
            - int: Number of duplicate reads ignored

    Raises:
        SystemExit: If the BAM directory does not exist (exit code 66)
    """
    bam_path = Path(bam_dir)
    if not bam_path.is_dir():
        print(f"[ERROR] BAM dir does not exist: {bam_dir}")
        sys.exit(66)  # EX_NOINPUT - input directory does not exist

    print(f"[INFO] Scanning BAM directory: {bam_dir}")

    # Set to store unique parent IDs (pIDs) of reads aligned to chrM
    # For split reads, this will be the parent ID from pi:Z tag
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
                        id = read.query_name  # Get the read identifier
                        pid = ""  # Initialize parent ID

                        # Check if read has a parent ID tag (pi:Z) indicating it's a split read
                        if read.has_tag("pi:Z"):
                            read_split_count += 1
                            pid = read.get_tag("pi:Z")  # Extract parent ID from tag
                            if verbose:
                                print(
                                    f"[INFO]    Subread ID# {id} was generated from Parent read pID# {pid} [READ SPLITTING]"
                                )
                        else:
                            # No split read tag, so parent ID is the same as read ID
                            pid = id
                            if verbose:
                                print(f"[INFO]    Read pID# {pid}")

                        # Check if this parent ID has already been encountered (avoid duplicates)
                        if pid in pids:
                            read_duplicate_count += 1
                            if verbose:
                                print(
                                    "[INFO]       Duplicate entry (not re-stored) [DUPLICATE]"
                                )
                        else:
                            # Add new unique parent ID to the set
                            pids.add(pid)  # Use add() for sets, not append()
                            if verbose:
                                print("      [OK] Storing entry")

                            # Verify that the parent ID exists in the Pod5 data
                            if (
                                pid in pod5_ids
                            ):  # Use pod5_ids parameter instead of undefined allids
                                if verbose:
                                    print("      [OK] pID in Pod5 raw reads")
                            else:
                                # Parent ID found in BAM but missing from Pod5 data
                                missingids.append(pid)
                                if verbose:
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
    print(f"Script: get_chrMpid.py v.{VERSION} by {AUTHOR}")

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

    # Process BAM files to find chrM-aligned reads and their parent IDs
    (
        pids,  # Unique parent IDs
        missingids,  # IDs missing from Pod5 data
        bam_count,  # Number of BAM files processed
        read_chrM_count,  # Total reads aligned to chrM
        read_split_count,  # Split reads count
        read_duplicate_count,  # Duplicate reads ignored
    ) = get_chrM_pids(args.bam, pod5_ids, args.verbose)

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
