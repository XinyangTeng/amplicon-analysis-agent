from __future__ import annotations

import csv
import math
import random
from pathlib import Path


ROOT = Path(__file__).parents[1]
OUT = ROOT / "examples" / "comprehensive"
RNG = random.Random(20260728)
GROUPS = ("Control", "Drought", "Salt")
SAMPLES = [(f"{group}_{index:02d}", group, index) for group in GROUPS for index in range(1, 13)]
FEATURES = [f"ASV{index:03d}" for index in range(1, 61)]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "metadata.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["SampleID", "Group", "Batch", "StressIntensity", "SourceSink"])
        for sample, group, index in SAMPLES:
            writer.writerow([sample, group, "demo_batch", GROUPS.index(group), "Sink" if group == "Salt" else "Source"])

    with (OUT / "abundance.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["FeatureID", *[sample for sample, _, _ in SAMPLES]])
        for feature_index, feature in enumerate(FEATURES):
            row = [feature]
            signal_group = GROUPS[feature_index // 12] if feature_index < 36 else None
            for _, group, replicate in SAMPLES:
                baseline = 30 + (feature_index % 9) * 4
                signal = 150 if signal_group == group else 0
                gradient = (GROUPS.index(group) * 10) if feature_index % 7 == 0 else 0
                noise = RNG.randint(0, 35) + int(8 * math.sin(replicate + feature_index))
                value = max(0, baseline + signal + gradient + noise)
                if signal_group != group and (replicate + feature_index) % 5 == 0:
                    value = 0
                row.append(value)
            writer.writerow(row)

    ranks = ["Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species", "KO", "Pathway"]
    with (OUT / "taxonomy.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["FeatureID", *ranks])
        for index, feature in enumerate(FEATURES, 1):
            writer.writerow([
                feature, "Bacteria", f"Phylum_{(index - 1) % 6 + 1}",
                f"Class_{(index - 1) % 10 + 1}", f"Order_{(index - 1) % 15 + 1}",
                f"Family_{(index - 1) % 20 + 1}", f"Genus_{index}",
                f"Species_{index}", f"K{index:05d}", f"Pathway_{(index - 1) % 8 + 1}",
            ])

    def subtree(features: list[str], depth: int = 0) -> str:
        if len(features) == 1:
            index = FEATURES.index(features[0])
            return f"{features[0]}:{0.03 + (index % 7) * 0.005:.3f}"
        middle = len(features) // 2
        left = subtree(features[:middle], depth + 1)
        right = subtree(features[middle:], depth + 1)
        branch = 0.02 + depth * 0.004
        return f"({left},{right}):{branch:.3f}"

    (OUT / "tree.nwk").write_text(subtree(FEATURES) + ";\n", encoding="utf-8")
    sequence = "ACGT" * 25
    (OUT / "representative_sequences.fasta").write_text(
        "".join(f">{feature}\n{sequence}\n" for feature in FEATURES), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
