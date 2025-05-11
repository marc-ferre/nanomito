#!/usr/bin/python3
#
# get_chrMpid.py -b bam/dir -o chrM_pids.txt
#
# Script to get unique parent IDs (pid) of reads aligned (BAM) to chrM from nanopore sequencing
#
# Requires conda environment
#    name: /home/genouest/cnrs_umr6015_inserm_umr1083/mferre/bioapp/env_getmt
#    channels:
#      - anaconda
#      - conda-forge
#      - bioconda
#      - nodefaults
#    dependencies:
#      - pod5
#      - pysam
#
import optparse
import os
from pathlib import Path
import pysam
import pod5
import subprocess

version = "25.05.11.3"
author = "Marc FERRE <marc.ferre@univ-angers.fr>"


#
# Main
#
def main():

    print("Script: get_chrMpid.py v.", version, " by ", author, sep="")

    # Arguments

    parser = optparse.OptionParser()
    parser.add_option(
        "-b", "--bam", type="string", default="bam_pass", help="BAM alignments dir"
    )
    parser.add_option(
        "-p", "--pod5", type="string", default="pod5", help="POD5 raw data dir"
    )
    parser.add_option(
        "-o",
        "--output",
        type="string",
        default="chrM_pids.txt",
        help="a file containing a list of unique parent ids of reads matching to chrM",
    )
    (opts, args) = parser.parse_args()

    # Get IDS of all raw reads (POD5)
    pod5_path = Path(opts.pod5)
    try:
        my_abs_path = pod5_path.resolve(strict=True)
    except FileNotFoundError:
        print("[ERROR] POD5 dir does not exist:", opts.pod5)
        exit(66)
    else:
        print("POD5 dir:", opts.pod5)

    allids = set()
    allids_count = 0
    with pod5.DatasetReader(opts.pod5, recursive=True) as dataset:
        for read_record in dataset:
            allids_count += 1
            allids.add(read_record.read_id)

    print("Raw reads (Pod5) stored:", allids_count)

    # Get parent IDs of reads matching chrM
    bam_path = Path(opts.bam)
    try:
        my_abs_path = bam_path.resolve(strict=True)
    except FileNotFoundError:
        print("[ERROR] BAM dir does not exist:", opts.bam)
        exit(66)
    else:
        print("BAM dir:", opts.bam)

    bam_count = 0
    read_chrM_count = 0
    read_split_count = 0
    read_duplicate_count = 0
    read_unique_count = 0
    read_missing_count = 0

    # List fo raw data ID (Pod5) of reads aligned to chrM:
    #   Parent ID (pid) if read splitting,
    #   else Read ID
    pids = []

    for root, dirs, files in os.walk(opts.bam):
        for file in files:
            if file.endswith(".bam"):
                bam_count += 1
                sampath = os.path.join(root, file)
                print("Process file: ", sampath)

                samfile = pysam.AlignmentFile(sampath, "rb")

                for read in samfile.fetch("chrM"):
                    read_chrM_count += 1
                    id = read.query_name
                    pid = ""
                    if read.has_tag("pi:Z"):
                        read_split_count += 1
                        pid = read.get_tag("pi:Z")
                        print(
                            "   Subread id#",
                            id,
                            "was generated from Parent read pid#",
                            pid,
                            "[READ SPLITTING]",
                        )
                    else:
                        pid = id
                        print("   Read pid#", pid)

                    # Store pid if not duplicate
                    if pid in pids:
                        read_duplicate_count += 1
                        print(
                            "      Duplicate entry (not re-stored): pid#",
                            pid,
                            "[DUPLICATE]",
                        )
                    else:
                        read_unique_count += 1
                        pids.append(pid)
                        print("      Storing entry: pid#", pid)

                    # Check if BAM ID match POD5 ID
                    if pid in allids:
                        read_missing_count += 1
                        print(
                            "      [WARNING] BAM ID missing from POD5 IDs: pid#",
                            pid,
                            "[MISSING]",
                        )
                        print("                SAM read:")
                        print("-------------------------------------------------------")
                        print(read)
                        print("-------------------------------------------------------")

                samfile.close()

    print("\n| Raw reads (Pod5):", allids_count)
    print("| BAM files processed:", bam_count)
    print("| Reads aligned to chrM:", read_chrM_count)
    print("| Split reads:", read_split_count)
    print("| Duplicate reads ignored:", read_duplicate_count)
    print("| Unique Pod5 IDs:", read_unique_count)
    print("| Missing reads:", read_missing_count)

    # Write unique IDS to file
    out_path = Path(opts.output)
    f_pids_count = 0
    with open(out_path, "w") as f:
        for pid in pids:
            f.write(f"{pid}\n")
            f_pids_count += 1
    print(
        "\n[OK]",
        f_pids_count,
        "unique Pod5 IDs of reads aligned to chrM written to:",
        out_path,
        "\n",
    )


if __name__ == "__main__":
    main()
