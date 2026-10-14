import json
from pathlib import Path

base = Path(__file__).parent
SRC = base / "lefff_conjugations.json"
DST = base / "lefff_conjugations_50.json"

with open(SRC, "r", encoding="utf-8") as f:
    data = json.load(f)

subset = dict(list(data.items())[:50])

print(f"Nombre de verbes retenus : {len(subset)}")

with open(DST, "w", encoding="utf-8") as f:
    json.dump(subset, f, ensure_ascii=False, indent=2)

print("Fichier généré :", DST)