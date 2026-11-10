"""Common Voice 19 (CC0) through the fsicoli/common_voice_19_0 mirror on Hugging Face.

Mozilla now distributes Common Voice only through Mozilla Data Collective; the mirror keeps the
same per-split metadata and tar shards. Only the dev and test splits are used: each holds many
speakers with a few clips each, which is what a speaker-level model needs.
"""

import csv
import io
import sys
import tarfile
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE = "https://huggingface.co/datasets/fsicoli/common_voice_19_0/resolve/main"
SPLITS = ("dev", "test")
GENDERS = {"male_masculine": 0, "female_feminine": 1}
TIMEOUT = 120  # seconds without data
DATA = Path(__file__).resolve().parents[2] / ".build/voice-model/data/common_voice"

csv.field_size_limit(sys.maxsize)


def metadata(language: str, split: str) -> list[dict]:
    path = DATA / language / f"{split}.tsv"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(f"{BASE}/transcript/{language}/{split}.tsv", timeout=TIMEOUT) as response:
            path.write_bytes(response.read())
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def gendered_speakers(language: str) -> dict[int, set[str]]:
    speakers = defaultdict(set)
    for split in SPLITS:
        for row in metadata(language, split):
            if row.get("gender") in GENDERS:
                speakers[GENDERS[row["gender"]]].add(row["client_id"])
    return speakers


def clips(language: str, split: str, wanted: set[str]):
    """Yields (file name, mp3 bytes) for the wanted clips, streaming the split's tar shards."""
    shard = 0
    remaining = set(wanted)
    while remaining:
        url = f"{BASE}/audio/{language}/{split}/{language}_{split}_{shard}.tar"
        try:
            # A stalled download raises instead of hanging; the caller retries the language.
            response = urllib.request.urlopen(url, timeout=TIMEOUT)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return
            raise
        with tarfile.open(fileobj=response, mode="r|") as archive:
            for member in archive:
                name = Path(member.name).name
                if name in remaining:
                    remaining.discard(name)
                    yield name, archive.extractfile(member).read()
                    if not remaining:
                        return
        shard += 1


if __name__ == "__main__":
    import json
    languages = sys.argv[1:]
    counts = {}
    for language in languages:
        try:
            speakers = gendered_speakers(language)
        except Exception as error:
            print(language, "failed", error, file=sys.stderr)
            continue
        counts[language] = [len(speakers[0]), len(speakers[1])]
        print(language, counts[language], flush=True)
    (DATA / "speaker_counts.json").write_text(json.dumps(counts, indent=1))
