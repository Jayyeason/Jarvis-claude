import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional


MODELS_DIR = Path.home() / "Library" / "Application Support" / "Jarvis" / "Models"
MANIFEST_NAME = "manifest.json"

RECOMMENDED_MLX_MODELS = [
    {
        "repo_id": "mlx-community/Qwen2.5-3B-Instruct-4bit",
        "display_name": "Qwen2.5 3B Instruct 4bit",
        "notes": "轻量中文/英文文本模型，适合先验证端侧 OCR 识别链路。",
    },
    {
        "repo_id": "mlx-community/Qwen2.5-7B-Instruct-4bit",
        "display_name": "Qwen2.5 7B Instruct 4bit",
        "notes": "质量更高，占用内存和下载体积更大。",
    },
    {
        "repo_id": "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "display_name": "Llama 3.2 3B Instruct 4bit",
        "notes": "轻量英文表现较好的备选模型。",
    },
]


def safe_model_id(repo_id: str) -> str:
    normalized = repo_id.strip().replace("\\", "/")
    if not normalized:
        raise ValueError("repo_id is required")
    safe = normalized.replace("/", "--")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "-", safe).strip("-")
    if not safe:
        raise ValueError("repo_id is invalid")
    return safe[:160]


def default_display_name(repo_id: str) -> str:
    leaf = repo_id.rstrip("/").split("/")[-1]
    return leaf.replace("-", " ").replace("_", " ")


class LocalModelRegistry:
    def __init__(self, models_dir: Path = MODELS_DIR):
        self.models_dir = models_dir

    def ensure_dir(self) -> None:
        self.models_dir.mkdir(parents=True, exist_ok=True)

    def model_path(self, model_id: str) -> Path:
        return self.models_dir / safe_model_id(model_id)

    def manifest_path(self, model_id: str) -> Path:
        return self.model_path(model_id) / MANIFEST_NAME

    def build_manifest(
        self,
        repo_id: str,
        display_name: Optional[str] = None,
        revision: Optional[str] = None,
    ) -> dict:
        model_id = safe_model_id(repo_id)
        return {
            "id": model_id,
            "kind": "local",
            "engine": "mlx",
            "repo_id": repo_id.strip(),
            "display_name": display_name.strip() if display_name else default_display_name(repo_id),
            "revision": revision,
            "supports_vision": False,
            "installed_at": datetime.now(timezone.utc).isoformat(),
            "local_path": str(self.model_path(model_id)),
        }

    def write_manifest(self, manifest: dict) -> dict:
        model_id = manifest["id"]
        target = self.model_path(model_id)
        target.mkdir(parents=True, exist_ok=True)
        manifest["local_path"] = str(target)
        self.manifest_path(model_id).write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        return manifest

    def list_models(self) -> list[dict]:
        self.ensure_dir()
        models: list[dict] = []
        for manifest_path in sorted(self.models_dir.glob(f"*/{MANIFEST_NAME}")):
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
                manifest["local_path"] = str(manifest_path.parent)
                models.append(manifest)
            except Exception:
                continue
        return sorted(models, key=lambda m: (m.get("display_name") or m.get("repo_id") or "").lower())

    def get_model(self, model_id: str) -> dict:
        manifest_path = self.manifest_path(model_id)
        if not manifest_path.exists():
            raise FileNotFoundError(f"Local model not installed: {model_id}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["local_path"] = str(manifest_path.parent)
        return manifest

    def delete_model(self, model_id: str) -> None:
        target = self.model_path(model_id)
        if not target.exists():
            raise FileNotFoundError(f"Local model not installed: {model_id}")
        shutil.rmtree(target)
