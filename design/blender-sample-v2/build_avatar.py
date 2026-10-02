"""Blender remodel using verified official MakeHuman CC0 core assets.

Retains natural body/face/hand topology, fits clothes to the morphed mesh,
preserves source UVs and uses actual skin/fabric/hair textures.
"""
import bpy
import bmesh
import json
import math
import re
import struct
from array import array
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parent
CORE = OUT / 'source/core'
ASSETS = OUT / 'source/system_assets'
TEXTURES = OUT / 'textures'
TEXTURES.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
avatar = bpy.data.collections.new('AVATAR • CC0 base + Blender remodeling')
studio = bpy.data.collections.new('STUDIO • not exported')
bpy.context.scene.collection.children.link(avatar)
bpy.context.scene.collection.children.link(studio)


def read_obj(path):
    vertices, uvs, faces = [], [], []
    group = ''
    for line in path.read_text().splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == 'v':
            vertices.append(Vector(map(float, fields[1:4])))
        elif fields[0] == 'vt':
            uvs.append(tuple(map(float, fields[1:3])))
        elif fields[0] == 'g':
            group = ' '.join(fields[1:])
        elif fields[0] == 'f':
            indices, uv_indices = [], []
            for field in fields[1:]:
                bits = field.split('/')
                index = int(bits[0])
                indices.append(index - 1 if index > 0 else len(vertices) + index)
                uv_indices.append(int(bits[1]) - 1 if len(bits) > 1 and bits[1] else -1)
            faces.append((indices, uv_indices, group))
    return vertices, uvs, faces


base, base_uvs, base_faces = read_obj(CORE / 'base.obj')
morphed = [point.copy() for point in base]
for name, influence in [('asian-male-young.target', 1.0), ('muscle.target', .12)]:
    for line in (CORE / name).read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        fields = line.split()
        if len(fields) == 4:
            morphed[int(fields[0])] += Vector(map(float, fields[1:])) * influence
body_faces = [f for f in base_faces if f[2] == 'body']
body_indices = {v for face, _, _ in body_faces for v in face}
ground = min(morphed[i].y for i in body_indices)
height = max(morphed[i].y for i in body_indices) - ground
scale = 1.78 / height


def world(point):
    return (point.x * scale, -point.z * scale, (point.y - ground) * scale)


def proxy_fit(path):
    rows, deletes = [], set()
    scales = [1.0, 1.0, 1.0]
    mode = None
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split()
        if fields[0] in ['x_scale', 'y_scale', 'z_scale']:
            axis = 'xyz'.index(fields[0][0])
            a, b = int(fields[1]), int(fields[2])
            scales[axis] = abs(morphed[a][axis] - morphed[b][axis]) / float(fields[3])
        elif fields[0] == 'verts':
            mode = 'verts'
        elif fields[0] == 'delete_verts':
            mode = 'delete'
        elif fields[0][0].isalpha():
            mode = None
        elif mode == 'verts':
            if len(fields) == 1:
                rows.append(morphed[int(fields[0])].copy())
            elif len(fields) >= 9:
                indices = list(map(int, fields[:3]))
                weights = list(map(float, fields[3:6]))
                offset = list(map(float, fields[6:9]))
                point = sum((morphed[i] * w for i, w in zip(indices, weights)), Vector())
                point += Vector(offset[i] * scales[i] for i in range(3))
                rows.append(point)
        elif mode == 'delete':
            i = 0
            while i < len(fields):
                if i + 2 < len(fields) and fields[i + 1] == '-':
                    deletes.update(range(int(fields[i]), int(fields[i + 2]) + 1))
                    i += 3
                else:
                    deletes.add(int(fields[i]))
                    i += 1
    return rows, deletes


def texture(path, label, maximum, alpha=False, normal=False):
    assert path.exists(), 'Texture not ready: ' + str(path)
    image = bpy.data.images.load(str(path), check_existing=False)
    # Load the pixel buffer before changing the output path; Blender loads file
    # images lazily and otherwise tries to read the not-yet-created JPEG.
    _ = image.pixels[0]
    image.colorspace_settings.name = 'Non-Color' if normal else 'sRGB'
    w, h = image.size[:]
    if max(w, h) > maximum:
        ratio = maximum / max(w, h)
        image.scale(round(w * ratio), round(h * ratio))
    suffix = '.png' if alpha or normal else '.jpg'
    output_path = TEXTURES / (label + suffix)
    w, h = image.size[:]
    pixels = array('f', [0]) * (w * h * 4)
    image.pixels.foreach_get(pixels)
    generated = bpy.data.images.new(label + ' mobile texture', width=w, height=h, alpha=alpha or normal)
    generated.colorspace_settings.name = 'Non-Color' if normal else 'sRGB'
    generated.file_format = 'PNG' if suffix == '.png' else 'JPEG'
    generated.pixels.foreach_set(pixels)
    generated.save(filepath=str(output_path), quality=90)
    optimized = bpy.data.images.load(str(output_path), check_existing=False)
    optimized.colorspace_settings.name = 'Non-Color' if normal else 'sRGB'
    optimized.pack()
    return optimized


def material(name, diffuse_path, roughness, maximum=1024, alpha=False, normal_path=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = not alpha
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = 0
    shader.inputs['Specular IOR Level'].default_value = .24 if name == 'Skin' else .30
    node = mat.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = texture(diffuse_path, name.lower(), maximum, alpha)
    mat.node_tree.links.new(node.outputs['Color'], shader.inputs['Base Color'])
    if alpha:
        mat.surface_render_method = 'DITHERED'
        mat.node_tree.links.new(node.outputs['Alpha'], shader.inputs['Alpha'])
    if normal_path is not None and normal_path.exists():
        node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = texture(normal_path, name.lower() + '-normal', 1024, normal=True)
        normal = mat.node_tree.nodes.new('ShaderNodeNormalMap')
        normal.inputs['Strength'].default_value = .45
        mat.node_tree.links.new(node.outputs['Color'], normal.inputs['Color'])
        mat.node_tree.links.new(normal.outputs['Normal'], shader.inputs['Normal'])
    return mat


def create_mesh(name, positions, uvs, faces, mat, subdiv=0):
    used = sorted({i for indices, _, _ in faces for i in indices})
    remap = {original: i for i, original in enumerate(used)}
    data = bpy.data.meshes.new(name + ' topology')
    data.from_pydata([world(positions[i]) for i in used], [],
                     [[remap[i] for i in face] for face, _, _ in faces])
    data.update()
    layer = data.uv_layers.new(name='Source UV')
    for polygon, (_, uv_indices, _) in zip(data.polygons, faces):
        for loop, uv in zip(polygon.loop_indices, uv_indices):
            layer.data[loop].uv = uvs[uv] if uv >= 0 else (0, 0)
        polygon.use_smooth = True
    obj = bpy.data.objects.new(name, data)
    avatar.objects.link(obj)
    data.materials.append(mat)
    if subdiv:
        mod = obj.modifiers.new('Natural surface refinement', 'SUBSURF')
        mod.levels = subdiv
        mod.render_levels = subdiv
    return obj


wear = [
    ('Tailored casual outfit', 'clothes/male_casualsuit01/male_casualsuit01', .82),
    ('Shoes', 'clothes/shoes01/shoes01', .72),
    ('Hair', 'hair/short01/short01', .72),
    ('Eyes', 'eyes/low-poly/low-poly', .24),
    ('Eyebrows', 'eyebrows/eyebrow001/eyebrow001', .85),
    ('Eyelashes', 'eyelashes/eyelashes01/eyelashes01', .85),
]
attachments, hidden = [], set()
for name, stem, rough in wear:
    path = ASSETS / stem
    original, uvs, faces = read_obj(path.with_suffix('.obj'))
    fitted, deleted = proxy_fit(path.with_suffix('.mhclo'))
    assert len(fitted) == len(original), (name, len(fitted), len(original))
    hidden.update(deleted)
    attachments.append((name, stem, rough, fitted, uvs, faces))

skin = material('Skin', ASSETS/'skins/young_asian_male/young_lightskinned_male_diffuse3.png', .66, 2048)
kept_body = [f for f in body_faces if not all(i in hidden for i in f[0])]
body = create_mesh('Continuous anatomical body', morphed, base_uvs, kept_body, skin, 2)
for name, stem, rough, positions, uvs, faces in attachments:
    path = ASSETS / stem
    if name == 'Eyes':
        diffuse = ASSETS / 'eyes/materials/brown_eye.png'
    elif name in ['Eyebrows', 'Eyelashes']:
        diffuse = path.with_suffix('.png')
    else:
        diffuse = path.with_name(path.name + '_diffuse.png')
    normal_path = path.with_name(path.name + '_normal.png')
    mat = material(name, diffuse, rough, 1024,
                   alpha=name in ['Hair', 'Eyes', 'Eyebrows', 'Eyelashes', 'Tailored casual outfit'],
                   normal_path=normal_path)
    create_mesh(name, positions, uvs, faces, mat, 1 if name in ['Tailored casual outfit', 'Shoes'] else 0)

# Ground all dressed objects on their actual lowest sole, not a guessed ankle.
lowest = min((obj.matrix_world @ Vector(corner)).z for obj in avatar.objects for corner in obj.bound_box)
for obj in avatar.objects:
    obj.location.z -= lowest

parts = list(avatar.objects)
# Bake subtle skin microstructure to a real normal texture, rather than relying
# on Blender-only procedural nodes that disappear in a mobile GLB.
noise = skin.node_tree.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 210
noise.inputs['Detail'].default_value = 2
bump = skin.node_tree.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = .20
bump.inputs['Distance'].default_value = .00035
skin.node_tree.links.new(noise.outputs['Fac'], bump.inputs['Height'])
shader = skin.node_tree.nodes.get('Principled BSDF')
skin.node_tree.links.new(bump.outputs['Normal'], shader.inputs['Normal'])
normal_image = bpy.data.images.new('Skin microstructure normal', width=1024, height=1024, alpha=False)
normal_image.colorspace_settings.name = 'Non-Color'
target = skin.node_tree.nodes.new('ShaderNodeTexImage')
target.image = normal_image
skin.node_tree.nodes.active = target
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 4
scene.render.threads_mode = 'FIXED'; scene.render.threads = 4
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.bake(type='NORMAL', use_clear=True, margin=12)
normal_image.file_format = 'PNG'
normal_image.save(filepath=str(TEXTURES / 'skin-normal.png'))
normal_image.pack()
normal_node = skin.node_tree.nodes.new('ShaderNodeNormalMap')
normal_node.inputs['Strength'].default_value = .45
skin.node_tree.links.new(target.outputs['Color'], normal_node.inputs['Color'])
skin.node_tree.links.new(normal_node.outputs['Normal'], shader.inputs['Normal'])
bpy.ops.object.select_all(action='DESELECT')
temp = bpy.data.collections.new('TEMP mobile export')
bpy.context.scene.collection.children.link(temp)
copies = []
for original in parts:
    duplicate = original.copy()
    duplicate.data = original.data.copy()
    for mod in duplicate.modifiers:
        if mod.type == 'SUBSURF':
            mod.levels = min(1, mod.levels)
            mod.render_levels = min(1, mod.render_levels)
    temp.objects.link(duplicate)
    duplicate.select_set(True)
    copies.append(duplicate)
bpy.context.view_layer.objects.active = copies[0]
bpy.ops.object.convert(target='MESH')
for obj in list(temp.objects):
    if len(obj.data.polygons) > 1200:
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new('Mobile surface reduction', 'DECIMATE')
        mod.ratio = .76 if 'body' in obj.name.lower() else .42
        bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.context.view_layer.objects.active = list(temp.objects)[0]
bpy.ops.object.join()
mobile = bpy.context.object
mobile.name = 'HumanTwin_Adult_Avatar_V2'
props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
options = dict(filepath=str(OUT/'humantwin_avatar_v2.glb'), export_format='GLB',
    use_selection=True, export_apply=True, export_yup=True, export_animations=False,
    export_cameras=False, export_lights=False, export_extras=True, export_image_format='AUTO')
bpy.ops.export_scene.gltf(**{k:v for k,v in options.items() if k in props})
bpy.data.objects.remove(mobile, do_unlink=True)
bpy.data.collections.remove(temp)
path = OUT / 'humantwin_avatar_v2.glb'
raw = path.read_bytes();n,t = struct.unpack_from('<II',raw,12)
document = json.loads(raw[20:20+n])
copyright_text = 'MakeHuman Community official core assets (CC0-1.0). Body shaping, garment fitting, material refinement and export by HumanTwin AI in Blender. Synthetic demonstration model; no user photos.'
document['asset']['copyright'] = copyright_text
document['asset']['extras'] = {'humantwin': {'assetId':'humantwin-avatar-v2',
    'source':'makehuman-core-cc0-blender-remodel', 'license':'CC0-1.0',
    'baseSource':'https://github.com/makehumancommunity/makehuman',
    'modelOrigin':'simulatedSample','reconstructedFromPhotos':False,'createdDate':'2026-10-01'}}
for mat in document.get('materials', []):
    if mat.get('name') in ['Tailored casual outfit', 'Eyebrows', 'Eyelashes']:
        mat['alphaMode'] = 'MASK'
        mat['alphaCutoff'] = .45 if mat.get('name') == 'Tailored casual outfit' else .25
encoded = json.dumps(document,separators=(',',':')).encode();encoded += b' '*((-len(encoded))%4)
rest = raw[20+n:]
path.write_bytes(struct.pack('<4sII',b'glTF',2,20+len(encoded)+len(rest)) + struct.pack('<II',len(encoded),0x4E4F534A) + encoded + rest)

# Presentation studio. No studio props, lights or camera are included in the GLB.
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.render.engine = 'BLENDER_EEVEE'
scene.render.threads_mode = 'FIXED';scene.render.threads=4
scene.view_settings.view_transform='AgX'
scene.world.use_nodes=True
background = scene.world.node_tree.nodes.get('Background')
background.inputs[0].default_value=(.055,.068,.085,1)
background.inputs[1].default_value=.45


def aim(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def area(name, pos, power, size, color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.size=size;data.shape='DISK';data.color=color
    obj=bpy.data.objects.new(name,data);studio.objects.link(obj);obj.location=pos;aim(obj,(0,0,1))


area('Large soft key',(-3,-4,4.5),450,4,(1,.96,.91))
area('Gentle frontal fill',(3,-3,2.8),260,3,(.83,.91,1))
area('Blue rear edge',(1.5,2.5,3),550,2,(.4,.64,1))
floor_material=bpy.data.materials.new('Matte studio floor');floor_material.diffuse_color=(.027,.036,.048,1)
floor_material.use_nodes=True
floor_material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.027,.036,.048,1)
floor_material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.8
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003))
floor=bpy.context.object
for c in list(floor.users_collection):c.objects.unlink(floor)
studio.objects.link(floor);floor.data.materials.append(floor_material)
camera_data=bpy.data.cameras.new('Portrait camera');camera=bpy.data.objects.new('Portrait camera',camera_data)
studio.objects.link(camera);camera_data.type='ORTHO';camera_data.ortho_scale=2.06
camera.location=(1.5,-6,1.65);aim(camera,(0,0,.94));scene.camera=camera
scene.render.resolution_percentage=100
scene.render.resolution_x=960;scene.render.resolution_y=1200
scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.render.film_transparent=False
scene.render.filepath=str(OUT/'preview-front.png');bpy.ops.render.render(write_still=True)
camera.location=(-1.3,6,1.7);aim(camera,(0,0,.94))
scene.render.filepath=str(OUT/'preview-back.png');bpy.ops.render.render(write_still=True)
camera_data.ortho_scale=.47
camera.location=(.12,-4,1.69);aim(camera,(0,-.015,1.665))
scene.render.resolution_x=800;scene.render.resolution_y=800
scene.render.filepath=str(OUT/'preview-face.png');bpy.ops.render.render(write_still=True)
camera_data.ortho_scale=.35
camera.location=(.72,-3.5,1.00);aim(camera,(.47,-.03,.97))
scene.render.filepath=str(OUT/'preview-hand.png');bpy.ops.render.render(write_still=True)
camera_data.ortho_scale=2.06
camera.location=(.45,-6,1.6);aim(camera,(0,0,.94))
floor.hide_render=True;scene.render.film_transparent=True
scene.render.resolution_x=512;scene.render.resolution_y=640
scene.render.filepath=str(OUT/'thumb_sample.png');bpy.ops.render.render(write_still=True)
floor.hide_render=False;scene.render.film_transparent=False
scene.render.resolution_x=960;scene.render.resolution_y=1200
camera.location=(1.5,-6,1.65);aim(camera,(0,0,.94))
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'humantwin_avatar_v2.blend'))
report={'blenderVersion':bpy.app.version_string,'editableObjects':len(parts),
    'bodyFacesAfterClothingMask':len(kept_body),'glbBytes':path.stat().st_size,
    'meshCount':len(document.get('meshes',[])),'imageCount':len(document.get('images',[])),
    'source':'MakeHuman official CC0 core assets remodeled in Blender','usesUserPhotos':False}
(OUT/'creation-report.json').write_text(json.dumps(report,indent=2)+'\n')
print('HUMANTWIN_V2_CREATED',json.dumps(report))
