# Third-Party Notices

## Current bundled demonstration avatar

`assets/models/human_demo.glb` is the refined v2 demonstration avatar, based on
official MakeHuman Community core assets released under CC0 1.0 Universal.
Blender processing includes body-shape adjustment, garment fitting, skin normal
baking, material refinement and a mobile GLB export. No user photos are used.

- Editable scene: produced by the included build script; the generated `.blend` is retained locally and omitted from this source archive.
- Reproducible source: `design/blender-sample-v2/build_avatar.py`.
- Official core mesh revision: `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`.
- Official source and license: [MakeHuman asset license](https://static.makehumancommunity.org/about/license.html),
  [repository license](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/LICENSE.md).
- Base mesh/targets/license evidence: `design/blender-sample-v2/source/core/`.
- Official skin, clothing, hair, eyebrow, eyelash and eye assets, with individual
  CRC32/SHA-256 verification: `design/blender-sample-v2/source/system_assets/manifest.json`.
- Model provenance is stored in the GLB `asset.copyright` and
  `asset.extras.humantwin` fields and preserved when exported from the app.
- The model is an illustrative, synthetic sample and is not reconstructed from
  the user's selected photos.

## Previous original procedural v1 avatar

The earlier original procedural sample is retained locally (not included in this source archive) in
`design/blender-sample-v1/humantwin_avatar_v1.glb` and its editable `.blend`.
Existing local v1 files retain their own original provenance on export.

## Legacy RiggedFigure 3D model

Before 2026-10-01, `assets/models/human_demo.glb` was an unmodified, renamed copy
of `RiggedFigure.glb`. The original is retained locally (not included in this source archive) at
`design/blender-sample-v1/pre-import/assets/models/human_demo.glb`.
Existing downloaded local samples are retained and keep their original source
and attribution when re-exported.

- Copyright: © 2017 Cesium; Cesium for Everything.
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/).
- Source: [KhronosGroup/glTF-Sample-Assets — RiggedFigure](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/RiggedFigure).
- Pinned source revision: `03251428e295f20d8c4a65ddbbd7dafe4f251c6d`.
- Local SHA-256: `d6be85417d3e256861ee733eea6916093a7af7c79c16366181fd8abcaeb38cf5`.

The legacy model was used as a lightweight, synthetic technical-validation
asset for the HumanTwin AI Flutter 3D viewer proof of concept.
