#!/usr/bin/env python3
#
# get_chrMpid.py -b bam/dir -p pod5/dir -o chrM_pids.txt
#
# Script to get unique parent IDs (pIDs) of reads aligned (BAM) to chrM from nanopore sequencing
#
# Requires conda environment:
#    channels:
#      - anaconda
#      - conda-forge
#      - bioconda
#      - nodefaults
#    dependencies:
#      - pod5
#      - pysam
#
import argparse
import os
from pathlib import Path
import sys
import pysam
import pod5

VERSION = "25.05.25.4"
AUTHOR = "Marc FERRE <marc.ferre@univ-angers.fr>"

def parse_args():
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
        "-o", "--output", type=str, default="chrM_pids.txt",
        help="Output file for unique parent IDs"
    )
    return parser.parse_args()

def get_pod5_ids(pod5_dir: str) -> set[str]:
    """Return set of all Pod5 read IDs in the directory."""
    pod5_path = Path(pod5_dir)
    if not pod5_path.is_dir():
        print(f"[ERROR] Pod5 dir does not exist: {pod5_dir}")
        sys.exit(66)
    allids = set()
    with pod5.DatasetReader(pod5_dir, recursive=True) as dataset:
        for read_record in dataset:
            allids.add(str(read_record.read_id))
    print(f"[INFO] Pod5 dir: {pod5_dir} | Raw reads (Pod5) stored: {len(allids)}")
    return allids

def get_chrM_pids(bam_dir: str, pod5_ids: set[str]) -> tuple[set[str], list[str], int, int, int, int]:
    """Return set of unique parent IDs for reads aligned to chrM."""
    bam_path = Path(bam_dir)
    if not bam_path.is_dir():
        print(f"[ERROR] BAM dir does not exist: {bam_dir}")
        sys.exit(66)
    print(f"[INFO] Scanning BAM directory: {bam_dir}")

    # List fo raw data ID (Pod5) of reads aligned to chrM:
    #   Parent ID (pID) if read splitting,
    #   else Read ID
    pids = set()
    # List of missing IDs (Pod5) of reads aligned to chrM
    missingids = []
    # Counters
    #   bam_count: number of BAM files processed
    #   read_chrM_count: number of reads aligned to chrM
    #   read_split_count: number of reads with pi:Z tag (split reads)
    #   read_duplicate_count: number of duplicate reads (same pID)
    bam_count = 0
    read_chrM_count = 0
    read_split_count = 0
    read_duplicate_count = 0

    for root, _, files in os.walk(bam_dir):
        for file in files:
            if file.endswith(".bam"):
                bam_count += 1
                sampath = os.path.join(root, file)
                print("[INFO] Processing BAM file: {sampath}")

                samfile = pysam.AlignmentFile(sampath, "rb")

                for read in samfile.fetch("chrM"):
                    read_chrM_count += 1
                    id = read.query_name
                    pid = ""
                    if read.has_tag("pi:Z"):
                        read_split_count += 1
                        pid = read.get_tag("pi:Z")
                        print("[INFO]    Subread ID# {id} was generated from Parent read pID# {pid} [READ SPLITTING]")
                    else:
                        pid = id
                        print("[INFO]    Read pID#", pid)

                    # Store pID if not duplicate
                    if pid in pids:
                        read_duplicate_count += 1
                        print("[INFO]       Duplicate entry (not re-stored) [DUPLICATE]")
                    else:
                        pids.append(pid)
                        print("      [OK] Storing entry")

                        # Check if BAM ID match Pod5 ID
                        if pid in allids:
                            print("      [OK] pID in Pod5 raw reads")
                        else:
                            missingids.append(pid)
                            print(
                                "      [WARNING] pID (BAM ID) missing from Pod5 IDs [MISSING]",
                            )
                            print("                SAM read:")
                            print("---------------------------------------------------")
                            print(read)
                            print("---------------------------------------------------")

                samfile.close()
    print(f"[INFO] Finished scanning all BAM files.")
    return pids, missingids, bam_count, read_chrM_count, read_split_count, read_duplicate_count

def write_ids(ids: set[str], output_file: str) -> None:
    with open(output_file, "w") as f:
        for pid in ids:
            f.write(f"{pid}\n")
    print(f"[OK] {len(ids)} unique Pod5 IDs of reads aligned to chrM written in file: {output_file}")

def main():
    print(f"Script: get_chrMpid.py v.{VERSION} by {AUTHOR}")
    args = parse_args()
    pod5_ids = get_pod5_ids(args.pod5)
    pids, missingids, bam_count, read_chrM_count, read_split_count, read_duplicate_count = get_chrM_pids(args.bam, pod5_ids)

    print("\n| Pod5 reads:", len(pod5_ids))
    print("| BAM files processed:", bam_count)
    print("| Reads aligned to chrM:", read_chrM_count)
    print("|   Split reads:", read_split_count)
    print("|   Duplicate reads ignored:", read_duplicate_count)
    print("|   Unique reads pIDs:", len(pids))
    print("|   Missing reads pIDs:", len(missingids))
    if missingids:
        print("\nMissing IDs:", missingids)
    write_ids(pids, args.output)

if __name__ == "__main__":
    main()