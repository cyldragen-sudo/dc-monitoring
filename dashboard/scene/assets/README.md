# Illustration provenance

These six raster assets are neutral AI-generated architectural/equipment illustrations. They contain no intended logos, text labels or operational health signals. The dashboard overlays database-backed labels, placement, occupancy and telemetry. Their depicted cabinet/building counts are composition choices, not inventory facts, and they are not interactive 3D models.

| File | Role | Recorded generation date |
|---|---|---|
| `network-scene.png` | Three-campus network overview; also embedded in FVS as `dc-network-scene.png` | 2026-10-25 |
| `campus.png` | Cutaway site context | 2026-10-26 |
| `hall.png` | Machine-room context | 2026-10-26 |
| `rack.png` | Empty rack frame behind accurate device overlays | 2026-10-26 |
| `server-front.png` | Generic server front texture for rack slots | 2026-10-26 |
| `server.png` | Generic server detail illustration | 2026-10-26 |

Generation used the built-in ImageGen tool and user-supplied concept references. [provenance.json](provenance.json) retains the five original English prompts, the campus correction prompt, final asset hashes and reference basenames. A separate network-scene record retains an English paraphrase of its original brief and its own generation date. Personal filesystem paths have been replaced with artifact basenames; original reference images are not included.

The five recorded final hashes were checked against the included files. The network asset hash was computed from the included final image. Verify every image against the manifest with standard Python:

```sh
python3 - <<'PY'
import hashlib, json
from pathlib import Path
assets = Path('dashboard/scene/assets')
for item in json.loads((assets / 'provenance.json').read_text())['final_assets']:
    actual = hashlib.sha256((assets / item['name']).read_bytes()).hexdigest()
    if actual != item['sha256']:
        raise SystemExit('Asset hash mismatch: ' + item['name'])
    print('OK', item['name'])
PY
```

Run from the repository root. Hashes establish file integrity, not authorship, uniqueness or rights clearance. AI illustration provenance is separate from the MIT project-code license; see [third-party notices](../../../THIRD_PARTY_NOTICES.md) for the reuse and reference-material boundary. Runtime screenshots elsewhere in the repository retain vendor UI/banner content and are not generated equipment assets.
