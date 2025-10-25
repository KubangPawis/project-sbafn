from pathlib import Path

from ultralytics import YOLO
import yaml

# --------------

REPO_ROOT = Path(__file__).resolve().parents[2]
MODELS_DIR = REPO_ROOT / "models"
CV_MODEL_DIR = MODELS_DIR / "cv-yolo-model"

with open(MODELS_DIR / "cv-yolo-model" / "configs" / "yolo11s_v1_01.yaml", "r", encoding="utf-8") as f:
    cfg_all = yaml.safe_load(f)

# CHOSEN MODEL
BEST_MODEL_PATH = REPO_ROOT / "models" / "cv-yolo-model" / "runs" / "y11s_baseline" / "weights" / "best.pt"

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
    
def export_model(model_weights_path: Path):
    best = model_weights_path
    if not best.exists():
        raise FileNotFoundError(best)

    # [CONFIGS] Set export configs
    export_params = dict((cfg_all.get("export") or {}))
    export_params.pop("enabled", None)

    # Setting defaults (in case not in .yaml)
    export_params.setdefault("format", "onnx")
    export_params.setdefault("imgsz", 640)
    export_params.setdefault("dynamic", True)
    export_params.setdefault("opset", 12)

    # [EXPORT] Model export based on export configs
    proj = export_params.get("project")
    if proj:
        Path(proj).mkdir(parents=True, exist_ok=True)

    model = YOLO(str(best))
    result = model.export(**export_params)
    export_dir = Path(export_params["project"]) / export_params["name"]
    print("Export dir:", export_dir.resolve())

    return result

if __name__ == "__main__":
    #run_yolo_model()
    export_model(model_weights_path=BEST_MODEL_PATH)