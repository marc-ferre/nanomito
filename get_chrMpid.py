#!/usr/bin/python3
#
# get_chrMpid.py -b bam/dir -o chrM_pids.txt
#
# Script to get unique parent IDs (pid) of reads aligned (BAM) to chrM from nanopore sequencing
#
import optparse
import os
from pathlib import Path
import pysam
import pod5
import subprocess

version = "25.05.04.2"
author = "Marc FERRE <marc.ferre@univ-angers.fr>"


def unique(list):
    unique_list = []
    for id in list:
        if id not in unique_list:
            unique_list.append(id)
    return unique_list


#
# Main
#
def main():

    print("Script: get_pid v.", version, " by ", author, sep="")

    # Arguments

    parser = optparse.OptionParser()
    parser.add_option(
        "-b", "--bam", type="string", default="bam_pass", help="BAM alignment dir"
    )
    parser.add_option(
        "-o",
        "--output",
        type="string",
        default="chrM_pids.txt",
        help="a file containing a list of parent ids of reads matching to chrM",
    )
    (opts, args) = parser.parse_args()

    # Get IDs of reads matching chrM

    bam_path = Path(opts.bam)
    try:
        my_abs_path = bam_path.resolve(strict=True)
    except FileNotFoundError:
        print("[ERROR] BAM dir does not exist:", opts.bam)
        exit(66)
    else:
        print("BAM dir:", opts.bam)

    pids = []
    for root, dirs, files in os.walk(opts.bam):
        for file in files:
            if file.endswith(".bam"):
                sampath = os.path.join(root, file)
                print("Process file: ", sampath)

                samfile = pysam.AlignmentFile(sampath, "rb")

                for read in samfile.fetch("chrM"):
                    if read.has_tag("pi:Z"):
                        id = read.get_tag("pi:Z")
                        pids.append(id)
                        print(
                            "   [READ SPLITTING] Subread id#",
                            read.query_name,
                            "was generated from Parent read id#",
                            id,
                        )
                    else:
                        id = read.query_name
                        pids.append(id)
                        print("   Read id#", id)

                samfile.close()

    print("\n\n>>> Parent IDs count:       ", len(pids))
    unique_pids = unique(pids)
    print(">>> Unique parent IDS count:", len(unique_pids))

    # Write unique ids file
    out_path = Path(opts.output)
    written_pids_count = 0
    with open(out_path, "w") as f:
        for id in unique_pids:
            f.write(f"{id}\n")
            written_pids_count += 1

    print(
        "[OK]",
        written_pids_count,
        "unique parent IDs of reads aligned to chrM written to:",
        out_path,
    )


if __name__ == "__main__":
    main()
