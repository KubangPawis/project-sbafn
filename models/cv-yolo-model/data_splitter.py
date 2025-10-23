from pathlib import Path
import shutil

import pandas as pd

# -------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
SHARD_NUMBER = 4

# -------------------

def segregate_train_val(images_dir: Path, v1_meta_path: Path, move=False):
    df = pd.read_csv(v1_meta_path)
    
    # Normalize
    norm = {"train":"train", "val":"val", "valid":"val", "validation":"val"}
    df["id"] = df["id"].astype(str).str.strip()
    df["split"] = df["split"].astype(str).str.strip().str.lower().map(norm)
    split_map = df.set_index("id")["split"].to_dict()

    temp_dir = images_dir / "temp"
    train_dir = images_dir / "train" / "labels"
    val_dir   = images_dir / "val" / "labels"
    train_dir.mkdir(parents=True, exist_ok=True)
    val_dir.mkdir(parents=True, exist_ok=True)

    op = shutil.move if move else shutil.copy2
    moved = skipped = 0

    if not temp_dir.exists():
        print("[!] /temp directory does not exist.")
        return

    for p in temp_dir.iterdir():
        if not p.is_file() or p.suffix.lower() != ".txt":
            continue
        file_id = p.stem.split("_")[0]
        split = split_map.get(file_id)
        if split not in {"train", "val"}:
            skipped += 1
            continue
        dst_dir = train_dir if split == "train" else val_dir
        op(str(p), str(dst_dir / p.name))
        moved += 1

    print(f"[Done] Labels moved={moved}, labels skipped={skipped}")

def make_ls_csv(shard_local_csv, out_csv):
    df = pd.read_csv(shard_local_csv)
    split = df["split"].str.lower().map({"validation":"val"}).fillna(df["split"].str.lower())

    def add_prefix(p, s):
        relative_path = f"data/annotation_v1_images/annotation_v1_shard{SHARD_NUMBER}_local"
        ls_prefix = "/data/local-files/?d=" # needed prefix for LS
        p = str(p).replace("\\", "/").lstrip("/")
        if p.startswith(("train/","val/","test/")):
            return p
        return f"{ls_prefix}{relative_path}/{s}/{p}"

    df["image"] = [add_prefix(p, s) for p, s in zip(df["image"], split)]
    df.to_csv(out_csv, index=False)

if __name__ == "__main__":
    target_file = f"annotation_v1_shard{SHARD_NUMBER}_local.csv"
    ls_file = f"annotation_v1_shard{SHARD_NUMBER}_ls.csv"
    v1_meta_out_dir = REPO_ROOT / "data" / "meta" / "v1"
    v1_images_dir = REPO_ROOT / "data" / "annotation_v1_images"

    v1_meta_out_dir.mkdir(parents=True, exist_ok=True)
    v1_images_dir.mkdir(parents=True, exist_ok=True)

    # To segregate train/val/test splits for CV model (YOLO)
    segregate_train_val(images_dir=v1_images_dir,
                        v1_meta_path=v1_meta_out_dir / "annotation_v1.csv")
    
    # To create a label studio manifest
    if not (v1_meta_out_dir / ls_file).exists():
        make_ls_csv(shard_local_csv=v1_meta_out_dir / target_file,
                    out_csv=v1_meta_out_dir / ls_file)
    else:
        print(f"[!] Manifest for Label Studio already exists.")
