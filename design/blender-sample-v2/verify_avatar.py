"""Reopen the .blend and independently import/render the exported GLB."""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(root / "humantwin_avatar_v2.blend"))
source = bpy.data.collections.get("AVATAR • CC0 base + Blender remodeling")
assert source and len(source.objects) == 7
source_objects = len(source.objects)
for obj in list(source.objects):
    bpy.data.objects.remove(obj, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
bpy.ops.import_scene.gltf(filepath=str(root / "humantwin_avatar_v2.glb"))
imported = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
assert imported, "No GLB mesh imported"
coords = [obj.matrix_world @ vertex.co for obj in imported for vertex in obj.data.vertices]
assert all(math.isfinite(component) for vertex in coords for component in vertex)
minimum = [min(vertex[i] for vertex in coords) for i in range(3)]
maximum = [max(vertex[i] for vertex in coords) for i in range(3)]
size = [maximum[i] - minimum[i] for i in range(3)]
assert 1.7 < size[2] < 2.0, size
assert .75 < size[0] < 1.6, size
assert .20 < size[1] < .65, size
assert all(len(obj.data.polygons) > 0 for obj in imported)
scene = bpy.context.scene
scene.render.resolution_x = 768
scene.render.resolution_y = 960
scene.render.filepath = str(root / "preview-imported-glb.png")
bpy.ops.render.render(write_still=True)
report = {
    "sourceSceneReopened": True,
    "sourceEditableObjects": source_objects,
    "glbImported": True,
    "importedMeshes": len(imported),
    "vertices": len(coords),
    "boundsMinimumMeters": minimum,
    "boundsMaximumMeters": maximum,
    "dimensionsMeters": size,
    "finiteGeometry": True,
    "glbRendered": True,
}
(root / "blender-verification.json").write_text(json.dumps(report, indent=2) + "\n")
print("HUMANTWIN_AVATAR_REOPEN_IMPORT_RENDER_PASS", json.dumps(report))
