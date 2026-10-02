PUBLIC SOURCE ARCHIVE NOTE

This directory contains the build/verification scripts, official CC0 inputs and license/hash evidence. Generated .blend, duplicate .glb, baked textures, previews, pre-import backups and app-verification.json are retained only in the local production workspace. The current runtime GLB and thumbnail are included at the repository-root assets/ paths. The production notes below name generated/local outputs, not additional files shipped here. Rebuilding needs a separately available Blender environment; no rebuild was run for this archive.

HumanTwin refined demonstration avatar v2 — 2026-10-01

The v2 uses the official MakeHuman Community CC0 core base mesh, body targets,
skin, casual clothing, shoes, hair, eyes, eyebrows and eyelashes. Blender fits
these to the shaped body, refines the surface and materials, bakes a skin normal
map, preserves texture alpha, and exports a mobile GLB. No user photos or real
generation API were used. This remains a synthetic sample, not photo reconstruction.

Editable high-detail source: humantwin_avatar_v2.blend (packed textures)
Optimized mobile export: humantwin_avatar_v2.glb
Source script: build_avatar.py
Independent reopen/import/render check: verify_avatar.py
Views: preview-front.png, preview-back.png, preview-face.png, preview-hand.png
Actual exported GLB render: preview-imported-glb.png
Default app assets: assets/models/human_demo.glb, assets/images/thumb_sample.png

Official inputs and their verified license/content evidence are under source/.
The body is reshaped before fitting accessories via the supplied proxy mappings;
no new software, add-on, Flutter dependency or paid API was installed or used.
The old procedural v1 model and old RiggedFigure sample are preserved separately,
and existing local models/records are not deleted. Export attribution follows the
actual file's provenance rather than assigning every sample the current source.

Evidence: creation-report.json, blender-verification.json,
asset-import-report.json and app-verification.json.
