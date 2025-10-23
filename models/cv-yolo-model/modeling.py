from pathlib import Path

from ultralytics import YOLO
import yaml

# --------------

REPO_ROOT = Path(__file__).resolve().parents[2]
MODELS_DIR = REPO_ROOT / "models"
CV_MODEL_DIR = MODELS_DIR / "cv-yolo-model"

with open(MODELS_DIR / "cv-yolo-model" / "configs" / "yolo11s_v1_01.yaml", "r", encoding="utf-8") as f:
    cfg_all = yaml.safe_load(f)

# --------------

def run_yolo_model():
    cfg = dict(cfg_all) # shallow copy
    model_name = cfg.pop("model")
    data = cfg.pop("data")

    model = YOLO(str(CV_MODEL_DIR / model_name))
    model.train(data=data, **cfg)

    model.val(data=data, split="val", save=True,
              project=cfg.get("project"), name=f"{cfg.get('name','run')}_val")
    model.val(data=data, split="test",
               project=cfg.get("project"), name=f"{cfg.get('name','run')}_test")

if __name__ == "__main__":
    run_yolo_model()