from pathlib import Path
import pandas as pd

# -------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
SHARD_NUMBER = 4

# -------------------

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
    out_dir = REPO_ROOT / "data" / "meta" / "v1"

    make_ls_csv(shard_local_csv=out_dir / target_file,
                out_csv=out_dir / ls_file)
