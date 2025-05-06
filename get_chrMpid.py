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
import sys

version = "25.05.05.2"
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

    # Dictionary of reads aligned to chrM
    #   Key: read id (BAM)
    #   Value: raw data id (Pod5): parent id if read splitting, else read id
    pids = {}
    print("Creating the dictionary with key: Read ID - value: Raw ID")

    for root, dirs, files in os.walk(opts.bam):
        for file in files:
            if file.endswith(".bam"):
                sampath = os.path.join(root, file)
                print("Process file: ", sampath)

                samfile = pysam.AlignmentFile(sampath, "rb")

                for read in samfile.fetch("chrM"):
                    read_id = read.query_name
                    raw_id = read_id
                    if read.has_tag("pi:Z"):
                        raw_id = read.get_tag("pi:Z")
                        print(
                            "   [READ SPLITTING] Subread id#",
                            read_id,
                            "was generated from Parent read id#",
                            raw_id,
                        )
                    else:
                        print("   Read id#", read_id)

                    # Test if entry exist
                    if read_id in pids:
                        if pids.get(read_id) == raw_id:
                            print(
                                "      [INFO] Existing entry not duplicated: Key read id#",
                                read_id,
                                "- Value raw id#",
                                raw_id,
                            )
                        else:
                            print(
                                "   [ERROR] Discordant existing entry: Key read id#",
                                read_id,
                                "- Value raw id#",
                                raw_id,
                            )
                            print(
                                "     is different from the new entry: Key read id#",
                                read_id,
                                "- Value raw id#",
                                pids.get(read_id),
                            )
                            sys.exit(
                                "[ERROR] Discordant existing entry: Key read id#",
                                read_id,
                                "- Value raw id#",
                                raw_id,
                            )
                    else:
                        pids.update({read_id: raw_id}
)
                        print(
                            "      Storing: Key read id#",
                            read_id,
                            "- Value raw id#",
                            raw_id,
                        )

                samfile.close()

    print("\n>>> Read-Raw IDs count:", len(pids.values()))
   
    # Write unique IDS to file

    out_path = Path(opts.output)
    written_pids_count = 0
    with open(out_path, "w") as f:
        for read_id, raw_id in pids.items():
            f.write(f"{read_id}\t{raw_id}\n")
            written_pids_count += 1

    print(
        "[OK]",
        written_pids_count,
        "parent IDs of reads aligned to chrM written to:",
        out_path,
    )


if __name__ == "__main__":
    main()
