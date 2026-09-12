#!/usr/bin/env python3
"""
analyze_shared_heteroplasmy.py
================================

Standalone, read-only analysis of variant and heteroplasmy concordance between:
  - Amplification-free long-read (Nanomito / Baldur: Oxford Nanopore long reads)
  - Long-range PCR short-read (Mitopore: Illumina short reads)

Verified file mapping from compare_vcf.sh and isec metadata:
  - 0000: Nanomito-specific calls (amplification-free long-read private)
  - 0001: Mitopore-specific calls (long-range PCR short-read private)
  - 0002: Shared calls in Nanomito representation (amplification-free long-read)
  - 0003: Shared calls in Mitopore representation (long-range PCR short-read)

Key pairing rule: CHROM + POS + REF + ALT (never position alone).
Primary quantitative scope: PASS-filtered shared SNVs (symbolic SVs, indels, DELs, DUPs excluded).
All heteroplasmy values expressed in percentage points (0 - 100%).
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

import matplotlib
matplotlib.use("Agg")
matplotlib.rcParams['pdf.fonttype'] = 42
matplotlib.rcParams['ps.fonttype'] = 42
import matplotlib.pyplot as plt

# --- Constants & Aliases ---
NANOMITO_SHARED_FILE = "0002"
MITOPORE_SHARED_FILE = "0003"

CHROM_ALIASES = {
    "chrm": "chrM",
    "mt": "chrM",
    "m": "chrM",
    "nc_012920.1": "chrM",
}
CHROM_CANONICAL = "chrM"

STRUCTURAL_ALT_RE = re.compile(r"[<>]")

SNV_10_SAMPLES = [
    "M11778-1",
    "M3243-1",
    "M3243-2",
    "M3243-3",
    "M3243-4",
    "M3243-5",
    "M3243-6",
    "M8344-1",
    "M8344-2",
    "M8344-3",
]

# --- Helper Functions ---

def normalize_chrom(val: str) -> str:
    k = str(val).strip().lower()
    return CHROM_ALIASES.get(k, str(val).strip())

def is_symbolic_alt(alt: str) -> bool:
    return any(STRUCTURAL_ALT_RE.search(a) for a in str(alt).split(","))

def parse_hpl_val(val_str: str) -> float:
    s = str(val_str).strip()
    if not s or s == ".":
        return np.nan
    first = s.split(",")[0].strip()
    try:
        v = float(first)
        if 0.0 <= v <= 1.0:
            return v * 100.0
        elif 1.0 < v <= 100.0:
            return v
        return v
    except ValueError:
        return np.nan

def load_file_tsv_or_vcf(filepath: Path, role: str) -> pd.DataFrame:
    if filepath.suffix == ".tsv":
        df = pd.read_csv(filepath, sep="\t", dtype=str, keep_default_na=False)
        df.columns = [c.strip() for c in df.columns]
        for c in df.columns:
            df[c] = df[c].astype(str).str.strip()
        
        if "HPL" not in df.columns and "AF" in df.columns:
            df["HPL"] = df["AF"]
        if "DP" not in df.columns:
            df["DP"] = "."
        if "FILTER" not in df.columns:
            df["FILTER"] = "PASS"
        return df
    else:
        header_lines = []
        data_lines = []
        col_names = []
        with open(filepath, "r") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("##"):
                    header_lines.append(line)
                elif line.startswith("#CHROM"):
                    col_names = line.lstrip("#").split("\t")
                elif line.strip():
                    data_lines.append(line)
        
        sample_cols = col_names[9:]
        rows = []
        for line in data_lines:
            cols = line.split("\t")
            rec = dict(zip(col_names, cols))
            chrom = rec.get("CHROM", "chrM")
            pos = rec.get("POS", "")
            ref = rec.get("REF", "")
            alt = rec.get("ALT", "")
            filt = rec.get("FILTER", "PASS")
            info = rec.get("INFO", "")
            fmt = rec.get("FORMAT", "")
            samp = rec.get(sample_cols[0], "") if sample_cols else ""
            
            hpl_val = "."
            dp_val = "."
            fmt_keys = fmt.split(":") if fmt else []
            fmt_vals = samp.split(":") if samp else []
            fmt_dict = dict(zip(fmt_keys, fmt_vals))
            
            if "HPL" in fmt_dict:
                hpl_val = fmt_dict["HPL"]
            elif "AF" in fmt_dict:
                hpl_val = fmt_dict["AF"]
            else:
                info_dict = {}
                for e in info.split(";"):
                    if "=" in e:
                        k, v = e.split("=", 1)
                        info_dict[k] = v
                hpl_val = info_dict.get("HPL", info_dict.get("AF", "."))
            
            dp_val = fmt_dict.get("DP", ".")
            
            rows.append({
                "CHROM": chrom, "POS": pos, "REF": ref, "ALT": alt,
                "FILTER": filt, "HPL": hpl_val, "DP": dp_val,
                "INFO": info
            })
        return pd.DataFrame(rows)

@dataclass
class QCRecord:
    Sample: str
    File_Type_Used: str
    Identity_Verified: bool
    Total_0000_Nanomito_Private: int = 0
    Total_0001_Mitopore_Private: int = 0
    Total_0002_Nanomito_Shared: int = 0
    Total_0003_Mitopore_Shared: int = 0
    Matched_Shared_PASS_SNVs: int = 0
    Matched_Shared_Indels: int = 0
    Excluded_Non_PASS: int = 0
    Excluded_Structural: int = 0
    Duplicate_Keys_Excluded: int = 0

def process_sample(sample_dir: Path) -> tuple[pd.DataFrame, QCRecord]:
    sample_id = sample_dir.name
    isec_dir = sample_dir / f"isec-{sample_id}"
    
    file_type = "tsv" if (isec_dir / "0002.tsv").exists() else "vcf"
    identity_verified = False
    
    readme_path = isec_dir / "README.txt"
    if readme_path.exists():
        txt = readme_path.read_text()
        if "0002.vcf" in txt and "nanopore_with_af" in txt and "0003.vcf" in txt and "illumina_copy" in txt:
            identity_verified = True
    
    ext = ".tsv" if file_type == "tsv" else ".vcf"
    p0 = isec_dir / f"0000{ext}"
    p1 = isec_dir / f"0001{ext}"
    p2 = isec_dir / f"0002{ext}"
    p3 = isec_dir / f"0003{ext}"
    
    df0 = load_file_tsv_or_vcf(p0, "Nanomito_private")
    df1 = load_file_tsv_or_vcf(p1, "Mitopore_private")
    df2 = load_file_tsv_or_vcf(p2, "Nanomito_shared")
    df3 = load_file_tsv_or_vcf(p3, "Mitopore_shared")
    
    qc = QCRecord(
        Sample=sample_id,
        File_Type_Used=file_type,
        Identity_Verified=identity_verified,
        Total_0000_Nanomito_Private=len(df0),
        Total_0001_Mitopore_Private=len(df1),
        Total_0002_Nanomito_Shared=len(df2),
        Total_0003_Mitopore_Shared=len(df3),
    )
    
    df2["CHROM_norm"] = df2["CHROM"].map(normalize_chrom)
    df3["CHROM_norm"] = df3["CHROM"].map(normalize_chrom)
    df2["POS_int"] = pd.to_numeric(df2["POS"], errors="coerce")
    df3["POS_int"] = pd.to_numeric(df3["POS"], errors="coerce")
    
    df2["HPL_pct"] = df2["HPL"].map(parse_hpl_val)
    df3["HPL_pct"] = df3["HPL"].map(parse_hpl_val)
    
    df2["key"] = df2["CHROM_norm"] + "|" + df2["POS_int"].astype(str) + "|" + df2["REF"] + "|" + df2["ALT"]
    df3["key"] = df3["CHROM_norm"] + "|" + df3["POS_int"].astype(str) + "|" + df3["REF"] + "|" + df3["ALT"]
    
    non_pass2 = df2["FILTER"].str.strip() != "PASS" if "FILTER" in df2 else pd.Series(False, index=df2.index)
    non_pass3 = df3["FILTER"].str.strip() != "PASS" if "FILTER" in df3 else pd.Series(False, index=df3.index)
    qc.Excluded_Non_PASS = int(non_pass2.sum() + non_pass3.sum())
    
    struct2 = df2["ALT"].map(is_symbolic_alt)
    struct3 = df3["ALT"].map(is_symbolic_alt)
    qc.Excluded_Structural = int(struct2.sum() + struct3.sum())
    
    clean2 = df2[(~non_pass2) & (~struct2)].copy()
    clean3 = df3[(~non_pass3) & (~struct3)].copy()
    
    dup2 = clean2.duplicated("key", keep=False)
    dup3 = clean3.duplicated("key", keep=False)
    qc.Duplicate_Keys_Excluded = int(dup2.sum() + dup3.sum())
    
    clean2 = clean2[~dup2]
    clean3 = clean3[~dup3]
    
    merged = clean2.merge(clean3, on="key", suffixes=("_nano", "_mito"))
    
    merged["is_snv"] = (merged["REF_nano"].str.len() == 1) & (merged["ALT_nano"].str.len() == 1)
    qc.Matched_Shared_PASS_SNVs = int(merged["is_snv"].sum())
    qc.Matched_Shared_Indels = int((~merged["is_snv"]).sum())
    
    shared_records = pd.DataFrame({
        "Sample": sample_id,
        "CHROM": merged["CHROM_norm_nano"],
        "POS": merged["POS_int_nano"].astype(int),
        "REF": merged["REF_nano"],
        "ALT": merged["ALT_nano"],
        "is_snv": merged["is_snv"],
        "Nanomito_HPL_pct": merged["HPL_pct_nano"],
        "Mitopore_HPL_pct": merged["HPL_pct_mito"],
        "Mean_HPL_pct": (merged["HPL_pct_nano"] + merged["HPL_pct_mito"]) / 2.0,
        "Difference_pp": merged["HPL_pct_nano"] - merged["HPL_pct_mito"],
        "Absolute_difference_pp": (merged["HPL_pct_nano"] - merged["HPL_pct_mito"]).abs(),
        "Below_95_in_either_workflow": (merged["HPL_pct_nano"] < 95.0) | (merged["HPL_pct_mito"] < 95.0),
        "Nanomito_DP": merged["DP_nano"],
        "Mitopore_DP": merged["DP_mito"],
    })
    
    return shared_records, qc

# --- Summary Statistics Calculator ---

def calculate_scope_stats(df: pd.DataFrame, scope_label: str) -> dict:
    n_samples = df["Sample"].nunique()
    n_pairs = len(df)
    diff = df["Difference_pp"]
    absdiff = df["Absolute_difference_pp"]
    
    med_diff = float(diff.median()) if n_pairs else np.nan
    q1_diff = float(diff.quantile(0.25)) if n_pairs else np.nan
    q3_diff = float(diff.quantile(0.75)) if n_pairs else np.nan
    med_absdiff = float(absdiff.median()) if n_pairs else np.nan
    
    n_nano_hi = int((diff > 0).sum())
    p_nano_hi = float(n_nano_hi / n_pairs * 100.0) if n_pairs else np.nan
    
    n_mito_hi = int((diff < 0).sum())
    p_mito_hi = float(n_mito_hi / n_pairs * 100.0) if n_pairs else np.nan
    
    n_gt5 = int((absdiff > 5.0).sum())
    
    return {
        "Analysis_Population": scope_label,
        "n_samples": n_samples,
        "n_pairs": n_pairs,
        "median_signed_difference_pp": round(med_diff, 2),
        "q1_signed_difference_pp": round(q1_diff, 2),
        "q3_signed_difference_pp": round(q3_diff, 2),
        "median_absolute_difference_pp": round(med_absdiff, 2),
        "n_amplification_free_higher": n_nano_hi,
        "prop_amplification_free_higher": round(p_nano_hi, 1),
        "n_long_range_pcr_higher": n_mito_hi,
        "prop_long_range_pcr_higher": round(p_mito_hi, 1),
        "n_abs_diff_gt_5pp": n_gt5,
    }

# --- Plotting ---

def make_publication_scatter_plot(df: pd.DataFrame, out_path_base: Path):
    plt.rcParams.update({
        "figure.dpi": 300,
        "savefig.dpi": 600,
        "font.size": 8.5,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "grid.alpha": 0.2,
        "font.family": "sans-serif",
    })
    
    fig, ax = plt.subplots(figsize=(4.8, 3.5))
    
    samples = sorted(df["Sample"].unique())
    colors = plt.cm.tab20(np.linspace(0, 1, len(samples)))
    
    for s, color in zip(samples, colors):
        sub = df[df["Sample"] == s]
        ax.scatter(
            sub["Mitopore_HPL_pct"], sub["Nanomito_HPL_pct"],
            s=26, alpha=0.8, color=color, label=s, edgecolor="none"
        )
    
    lims = [0, 100]
    ax.plot(lims, lims, linestyle="--", color="#555555", linewidth=1.0, label="y = x")
    ax.set_xlim(lims)
    ax.set_ylim(lims)
    ax.set_xlabel("Long-range PCR short-read heteroplasmy (%)", fontsize=9, fontweight="bold")
    ax.set_ylabel("Amplification-free long-read heteroplasmy (%)", fontsize=9, fontweight="bold")
    
    ax.legend(bbox_to_anchor=(1.02, 1.0), loc="upper left", frameon=True, fontsize=7.5, title="Sample ID", title_fontsize=8)
    
    pdf_path = out_path_base.with_suffix(".pdf")
    png_path = out_path_base.with_suffix(".png")
    fig.savefig(pdf_path, bbox_inches="tight")
    fig.savefig(png_path, bbox_inches="tight", dpi=600)
    plt.close(fig)

# --- Main Execution ---

def main():
    parser = argparse.ArgumentParser(description="Mitochondrial shared heteroplasmy concordance analysis.")
    parser.add_argument("input_root", type=Path, help="Root directory containing sample folders (Anonymized)")
    parser.add_argument("output_dir", type=Path, help="Output directory for generated tables and figures")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)

    sample_dirs = sorted([d for d in args.input_root.glob("*") if d.is_dir() and (d / f"isec-{d.name}").exists()])
    print(f"Discovered {len(sample_dirs)} sample directories with isec outputs.")

    all_shared_list = []
    qc_records = []

    for sdir in sample_dirs:
        shared_records, qc = process_sample(sdir)
        qc_records.append(qc)
        all_shared_list.append(shared_records)

    shared_df = pd.concat(all_shared_list, ignore_index=True)
    snv_df = shared_df[shared_df["is_snv"]].copy().reset_index(drop=True)

    # 1. Primary population: Complete 15-sample cohort
    all15_all = snv_df.copy()
    all15_below95 = snv_df[snv_df["Below_95_in_either_workflow"]].copy().reset_index(drop=True)

    # 2. Sensitivity population: 10-sample SNV sensitivity cohort
    snv10_all = snv_df[snv_df["Sample"].isin(SNV_10_SAMPLES)].copy().reset_index(drop=True)
    snv10_below95 = snv10_all[snv10_all["Below_95_in_either_workflow"]].copy().reset_index(drop=True)

    # Compute statistics for 4 scopes
    s1 = calculate_scope_stats(all15_all, "Complete 15-sample cohort, all shared PASS SNVs")
    s2 = calculate_scope_stats(all15_below95, "Complete 15-sample cohort, shared PASS SNVs below 95%")
    s3 = calculate_scope_stats(snv10_all, "10-sample SNV sensitivity cohort, all shared PASS SNVs")
    s4 = calculate_scope_stats(snv10_below95, "10-sample SNV sensitivity cohort, shared PASS SNVs below 95%")

    summary_by_analysis_df = pd.DataFrame([s1, s2, s3, s4])

    # Print numerical summary to console for verification
    print("\n" + "="*80)
    print("CONCISE NUMERICAL SUMMARY OF THE FOUR ANALYSES")
    print("="*80)
    for s in [s1, s2, s3, s4]:
        print(f"Scope: {s['Analysis_Population']}")
        print(f"  Samples: {s['n_samples']}, Matched Pairs: {s['n_pairs']}")
        print(f"  Median Signed Difference: {s['median_signed_difference_pp']:+.2f} pp (Q1: {s['q1_signed_difference_pp']:+.2f}, Q3: {s['q3_signed_difference_pp']:+.2f} pp)")
        print(f"  Median Absolute Difference: {s['median_absolute_difference_pp']:.2f} pp")
        print(f"  Amplification-free long-read higher: {s['n_amplification_free_higher']} ({s['prop_amplification_free_higher']}%)")
        print(f"  Long-range PCR short-read higher: {s['n_long_range_pcr_higher']} ({s['prop_long_range_pcr_higher']}%)")
        print(f"  Absolute difference > 5 pp: {s['n_abs_diff_gt_5pp']}")
        print("-" * 80)

    # Check DEL-1 technical control
    del1_df = snv_df[snv_df["Sample"] == "DEL-1"]
    del1_n = len(del1_df)
    del1_med_diff = del1_df["Difference_pp"].median()
    del1_med_absdiff = del1_df["Absolute_difference_pp"].median()
    print(f"\nDEL-1 Technical Control Check:")
    print(f"  Matched PASS SNVs: {del1_n} (expected 16)")
    print(f"  Median Signed Difference: {del1_med_diff:+.2f} pp (expected ~+0.36 pp)")
    print(f"  Median Absolute Difference: {del1_med_absdiff:.2f} pp (expected ~0.50 pp)\n")

    # Large differences (> 5.0 pp)
    large_all15 = all15_all[all15_all["Absolute_difference_pp"] > 5.0].copy()
    large_all15["Analysis_Population"] = "Complete 15-sample cohort"
    
    large_snv10 = snv10_all[snv10_all["Absolute_difference_pp"] > 5.0].copy()
    large_snv10["Analysis_Population"] = "10-sample SNV sensitivity cohort"

    large_diff_df = pd.concat([large_all15, large_snv10], ignore_index=True)
    large_diff_cols = ["Analysis_Population", "Sample", "CHROM", "POS", "REF", "ALT", "Nanomito_HPL_pct", "Mitopore_HPL_pct", "Difference_pp", "Absolute_difference_pp"]
    large_diff_df = large_diff_df[large_diff_cols].sort_values(["Analysis_Population", "Absolute_difference_pp"], ascending=[True, False]).reset_index(drop=True)

    # Save Required Tabular Outputs ONLY
    export_cols = ["Sample", "CHROM", "POS", "REF", "ALT", "Nanomito_HPL_pct", "Mitopore_HPL_pct", "Mean_HPL_pct", "Difference_pp", "Absolute_difference_pp", "Below_95_in_either_workflow", "Nanomito_DP", "Mitopore_DP"]
    
    all15_all[export_cols].to_csv(args.output_dir / "shared_snv_heteroplasmy_all15.tsv", sep="\t", index=False)
    all15_below95[export_cols].to_csv(args.output_dir / "shared_snv_heteroplasmy_below95_all15.tsv", sep="\t", index=False)
    snv10_all[export_cols].to_csv(args.output_dir / "shared_snv_heteroplasmy_snv10.tsv", sep="\t", index=False)
    snv10_below95[export_cols].to_csv(args.output_dir / "shared_snv_heteroplasmy_below95_snv10.tsv", sep="\t", index=False)
    
    summary_by_analysis_df.to_csv(args.output_dir / "summary_by_analysis.tsv", sep="\t", index=False)
    large_diff_df.to_csv(args.output_dir / "large_differences.tsv", sep="\t", index=False)
    
    qc_df = pd.DataFrame([q.__dict__ for q in qc_records])
    qc_df.to_csv(args.output_dir / "quality_control.tsv", sep="\t", index=False)

    # Clean up old TSV files if they exist from previous runs
    for old_file in ["shared_heteroplasmy_all.tsv", "shared_heteroplasmy_below_95.tsv", "nanomito_specific_calls.tsv", "mitopore_specific_calls.tsv", "summary_overall.tsv", "summary_by_sample.tsv", "recurrent_positions.tsv"]:
        p = args.output_dir / old_file
        if p.exists():
            p.unlink()

    # Generate Publication Figures
    make_publication_scatter_plot(all15_below95, args.output_dir / "shared_snv_heteroplasmy_below95_all15")
    make_publication_scatter_plot(snv10_below95, args.output_dir / "shared_snv_heteroplasmy_below95_snv10")

    # Clean up old plot and report files if they exist from previous runs
    for old_plot in ["shared_heteroplasmy_scatter_all", "shared_heteroplasmy_scatter_below_95", "shared_heteroplasmy_bland_altman_all", "shared_heteroplasmy_bland_altman_below_95"]:
        for ext in [".pdf", ".png"]:
            p = args.output_dir / f"{old_plot}{ext}"
            if p.exists():
                p.unlink()

    for old_report in ["shared_heteroplasmy_report.md", "shared_heteroplasmy_report_clean.md"]:
        p = args.output_dir / old_report
        if p.exists():
            p.unlink()

    print(f"Analysis complete. Generated tables and figures written to '{args.output_dir}'.")


if __name__ == "__main__":
    main()
