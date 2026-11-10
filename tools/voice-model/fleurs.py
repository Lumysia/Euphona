"""FLEURS (CC BY 4.0) dev splits as a second, independent test set: other speakers, other
microphones, other sentences, and languages Common Voice training never saw (such as Korean).

    uv run python fleurs.py [fleurs language codes...]
"""

import csv
import sys
import tarfile
import urllib.request
from concurrent.futures import ProcessPoolExecutor

import numpy as np

import augment
from extract import OUT, Encoder, pcm16, variant
from features import load_audio

BASE = "https://huggingface.co/datasets/google/fleurs/resolve/main/data"
# Not ja_jp: its dev split's FEMALE clips are male voices (median F0 106-120 Hz), so it tests the labels.
LANGUAGES = ("cmn_hans_cn", "en_us", "es_419", "fr_fr", "de_de", "ko_kr", "hi_in", "ar_eg",
             "ru_ru", "pt_br", "vi_vn", "th_th", "sw_ke", "yue_hant_hk", "ka_ge")
DATA = OUT.parent / "fleurs"


def recordings(language: str):
    folder = DATA / language
    folder.mkdir(parents=True, exist_ok=True)
    tsv = folder / "dev.tsv"
    if not tsv.exists():
        urllib.request.urlretrieve(f"{BASE}/{language}/dev.tsv", tsv)
    if not (folder / "dev").exists():
        with urllib.request.urlopen(f"{BASE}/{language}/audio/dev.tar.gz") as response:
            with tarfile.open(fileobj=response, mode="r|gz") as archive:
                archive.extractall(folder, filter="data")
    rows = list(csv.reader(open(tsv, encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
    return [(folder / "dev" / r[1], r[-1]) for r in rows if r[-1] in ("MALE", "FEMALE")]


def one(job):
    path, gender = job
    feminine = gender == "FEMALE"
    v = variant(load_audio(path), "recorded", augment.TIMBRE_HIGH if feminine else augment.TIMBRE_LOW)
    return path.name, int(feminine), v


def extract(language: str, encoder: Encoder, pool: ProcessPoolExecutor) -> None:
    target = OUT / f"fleurs-{language}.npz"
    if target.exists():
        return
    rows = {k: [] for k in ("speaker", "gender", "kind", "timbre")}
    embeddings, offsets = [], [0]
    for name, gender, v in pool.map(one, recordings(language), chunksize=4):
        if not v:
            continue
        vectors = encoder(v["crops"])
        embeddings.append(vectors.astype(np.float16))
        offsets.append(offsets[-1] + len(vectors))
        rows["speaker"].append(name)  # FLEURS has no speaker ids; each clip stands alone
        rows["gender"].append(gender)
        for key in ("kind", "timbre"):
            rows[key].append(v[key])
    np.savez_compressed(target, language=language, embeddings=np.concatenate(embeddings),
                        offsets=np.array(offsets), **{k: np.array(v) for k, v in rows.items()})
    print(language, len(rows["kind"]), "clips", offsets[-1], "windows", flush=True)


if __name__ == "__main__":
    encoder = Encoder()
    with ProcessPoolExecutor(max_workers=4) as pool:
        for language in sys.argv[1:] or LANGUAGES:
            try:
                extract(language, encoder, pool)
            except Exception as error:
                print(language, "failed:", repr(error), flush=True)
