#!/usr/bin/env python3
"""Convert Google's SCIN dataset into a SpotCheck evaluation manifest.

SCIN (Skin Condition Image Network) is a public dataset of smartphone photos
of skin conditions, contributed by US internet users and labeled by
dermatologists with a weighted differential. It suits SpotCheck well because
the photos look like what real users take. Check the dataset's license and
terms before using it for anything beyond internal evaluation:
https://github.com/google-research-datasets/scin

Usage:
  python3 eval/scin_to_manifest.py --out eval/data/scin/manifest.jsonl \
      --sample 300 --seed 7

The manifest references images by URL; the Dart runner downloads and caches
them. Only the Python standard library is required.
"""

import argparse
import ast
import csv
import io
import json
import random
import urllib.request
from pathlib import Path

BUCKET = "https://storage.googleapis.com/dx-scin-public-data"

# SCIN body-part flag -> SpotCheck site. Groin, genital, and buttock photos
# are out of scope for the app, so those cases are skipped.
SITE_PRIORITY = [
    ("body_parts_head_or_neck", "face"),
    ("body_parts_palm", "hand"),
    ("body_parts_back_of_hand", "hand"),
    ("body_parts_foot_sole", "foot"),
    ("body_parts_foot_top_or_side", "foot"),
    ("body_parts_arm", "arm"),
    ("body_parts_leg", "leg"),
    ("body_parts_torso_front", "torso"),
    ("body_parts_torso_back", "back"),
]
EXCLUDED_PARTS = ["body_parts_genitalia_or_groin", "body_parts_buttocks"]

AGE = {
    "AGE_18_TO_29": "18_39",
    "AGE_30_TO_39": "18_39",
    "AGE_40_TO_49": "40_64",
    "AGE_50_TO_59": "40_64",
    "AGE_60_TO_69": "65p",
    "AGE_70_TO_79": "65p",
    "AGE_80_OR_ABOVE": "65p",
}
SEX = {"FEMALE": "female", "MALE": "male"}
DURATION = {
    "ONE_DAY": "lt_1d",
    "LESS_THAN_ONE_WEEK": "1_6d",
    "ONE_TO_FOUR_WEEKS": "1_3w",
    "ONE_TO_THREE_MONTHS": "3w_3m",
    "THREE_TO_TWELVE_MONTHS": "3m_1y",
    "MORE_THAN_ONE_YEAR": "gt_1y",
    "MORE_THAN_FIVE_YEARS": "gt_1y",
    "SINCE_CHILDHOOD": "gt_1y",
    "UNKNOWN": "unknown",
}
KIND = {
    "RASH": "rash",
    "ACNE": "acne",
    "GROWTH_OR_MOLE": "mole",
    "PIGMENTARY_PROBLEM": "color_change",
}

# Conditions where missing the diagnosis or under-triaging causes real harm.
# Used to compute sensitivity on serious cases.
SERIOUS = {
    "melanoma": "routine",
    "basal cell carcinoma": "routine",
    "scc/sccis": "routine",
    "actinic keratosis": "routine",
    "cellulitis": "soon",
    "abscess": "soon",
    "herpes zoster": "soon",
    "leukocytoclastic vasculitis": "soon",
    "vasculitis of the skin": "soon",
    "purpura": "soon",
}


def fetch(name, cache_dir):
    path = cache_dir / name
    if not path.exists():
        cache_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {name}...")
        with urllib.request.urlopen(f"{BUCKET}/dataset/{name}") as r:
            path.write_bytes(r.read())
    return list(csv.DictReader(io.StringIO(path.read_text())))


def yes(row, key):
    return row.get(key) == "YES"


def convert(case, label):
    if label["dermatologist_gradable_for_skin_condition_1"] != (
        "DEFAULT_YES_IMAGE_QUALITY_SUFFICIENT"
    ):
        return None
    weights = label["weighted_skin_condition_label"]
    if not weights:
        return None
    weights = ast.literal_eval(weights)
    if not weights or any(yes(case, p) for p in EXCLUDED_PARTS):
        return None

    category = case["related_category"]
    if category == "NAIL_PROBLEM":
        site = "nail"
    elif category in ("HAIR_LOSS", "OTHER_HAIR_PROBLEM"):
        site = "scalp"
    else:
        site = next((s for flag, s in SITE_PRIORITY if yes(case, flag)), None)
    if site is None:
        return None

    answers = {}
    if case["age_group"] in AGE:
        answers["age_band"] = [AGE[case["age_group"]]]
    if case["sex_at_birth"] in SEX:
        answers["sex"] = [SEX[case["sex_at_birth"]]]
    fst = case["fitzpatrick_skin_type"]
    if fst.startswith("FST"):
        answers["skin_tone"] = [fst.lower()]
    if site not in ("nail", "scalp"):
        answers["skin_kind"] = [KIND.get(category, "other")]
    if case["condition_duration"] in DURATION:
        answers["duration"] = [DURATION[case["condition_duration"]]]

    local = [
        s
        for key, s in [
            ("condition_symptoms_itching", "itchy"),
            ("condition_symptoms_burning", "burning"),
            ("condition_symptoms_pain", "painful"),
        ]
        if yes(case, key)
    ]
    if local:
        answers["local_symptoms"] = local
    elif yes(case, "condition_symptoms_no_relevant_experience"):
        answers["local_symptoms"] = ["none"]

    change = [
        s
        for key, s in [
            ("condition_symptoms_increasing_size", "growing"),
            ("condition_symptoms_darkening", "color"),
            ("condition_symptoms_bleeding", "bleeding"),
        ]
        if yes(case, key)
    ]
    if change:
        answers["change"] = change

    general = [
        s
        for key, s in [
            ("other_symptoms_fever", "fever"),
            ("other_symptoms_chills", "fever"),
            ("other_symptoms_joint_pain", "joint_pain"),
            ("other_symptoms_mouth_sores", "mucosal_sores"),
            ("other_symptoms_shortness_of_breath", "trouble_breathing"),
        ]
        if yes(case, key)
    ]
    if general:
        answers["general_symptoms"] = sorted(set(general))
    elif yes(case, "other_symptoms_no_relevant_symptoms"):
        answers["general_symptoms"] = ["none"]

    images = []
    for i in (1, 2, 3):
        path = case[f"image_{i}_path"]
        if path:
            shot = case[f"image_{i}_shot_type"]
            images.append(
                {
                    "url": f"{BUCKET}/{path}",
                    "kind": "close_up" if shot == "CLOSE_UP" else "context",
                }
            )
    if not images:
        return None

    labels = sorted(
        ({"name": n, "weight": round(w, 3)} for n, w in weights.items()),
        key=lambda x: -x["weight"],
    )
    serious = [
        SERIOUS[l["name"].lower()]
        for l in labels
        if l["weight"] >= 0.3 and l["name"].lower() in SERIOUS
    ]
    entry = {
        "id": f"scin_{case['case_id']}",
        "source": "scin",
        "site": site,
        "images": images,
        "answers": answers,
        "labels": labels,
        "fitzpatrick": fst.lower() if fst.startswith("FST") else None,
    }
    if serious:
        order = ["self_care", "routine", "soon", "urgent", "emergency"]
        entry["serious"] = True
        entry["min_urgency"] = max(serious, key=order.index)
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default="eval/data/scin/manifest.jsonl")
    parser.add_argument("--cache", default="eval/data/scin")
    parser.add_argument(
        "--sample", type=int, default=0, help="Random sample size (0 = all)"
    )
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument(
        "--serious-first",
        action="store_true",
        help="Include every serious case before sampling the rest",
    )
    args = parser.parse_args()

    cache = Path(args.cache)
    cases = {r["case_id"]: r for r in fetch("scin_cases.csv", cache)}
    labels = {r["case_id"]: r for r in fetch("scin_labels.csv", cache)}

    entries = [
        e
        for cid in sorted(cases)
        if cid in labels
        for e in [convert(cases[cid], labels[cid])]
        if e is not None
    ]
    rng = random.Random(args.seed)
    if args.sample and args.sample < len(entries):
        if args.serious_first:
            serious = [e for e in entries if e.get("serious")]
            rest = [e for e in entries if not e.get("serious")]
            take = max(0, args.sample - len(serious))
            entries = serious[: args.sample] + rng.sample(rest, take)
        else:
            entries = rng.sample(entries, args.sample)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
    n_serious = sum(1 for e in entries if e.get("serious"))
    print(f"Wrote {len(entries)} cases ({n_serious} serious) to {out}")


if __name__ == "__main__":
    main()
