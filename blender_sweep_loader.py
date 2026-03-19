"""
blender_sweep_loader.py — Load NIMBY sweep city snapshots into Blender

Usage (interactive):
    Open Blender → Text Editor → Open this file → Run Script
    N-panel → "NIMBY Sweep" tab

Usage (headless batch render):
    blender --background --python blender_sweep_loader.py -- \\
            --sweep_dir sweep_results \\
            --output_dir renders \\
            --color_attr height

Reads the *_city.json files written by sweep.jl and renders each one.
Mesh geometry and colour logic are identical to blender_vis.py.
"""

bl_info = {
    "name":     "NIMBY Sweep Loader",
    "blender":  (3, 2, 0),
    "category": "Interface",
}

import bpy
import json
import math
import os
import sys
import traceback

import numpy as np

# ============================================================
# Constants  (identical to blender_vis.py)
# ============================================================

_GREY             = (0.75, 0.75, 0.75)
_LANDSCAPE_COLOR  = (0.04, 0.24, 0.06)
_NH_OBJ_PREFIX    = "NIMBY_NH_"
_SHARED_MAT_NAME  = "NIMBY_DwellingMat"
_ROADS_OBJ_NAME   = "NIMBY_Roads"
_ROADS_MAT_NAME   = "NIMBY_RoadsMat"
_ROAD_Z           = -4.0
_ROAD_BEVEL       = 0.3
_DWELLING_ALPHA   = 0.7
_LANDSCAPE_ALPHA  = 0.3

_CUBE_VERTS = [
    (-0.45, -0.45, -0.5), ( 0.45, -0.45, -0.5),
    ( 0.45,  0.45, -0.5), (-0.45,  0.45, -0.5),
    (-0.45, -0.45,  0.5), ( 0.45, -0.45,  0.5),
    ( 0.45,  0.45,  0.5), (-0.45,  0.45,  0.5),
]
_CUBE_FACES = [
    (0, 1, 2, 3), (4, 5, 6, 7),
    (0, 1, 5, 4), (2, 3, 7, 6),
    (0, 3, 7, 4), (1, 2, 6, 5),
]
_LOOPS_PER_DWELLING = len(_CUBE_FACES) * 4   # 24

_CUBE_VERTS_NP   = np.array(_CUBE_VERTS, dtype=np.float32)
_CUBE_LOOP_VERTS = np.array(
    [vi for face in _CUBE_FACES for vi in face], dtype=np.int32
)

# ============================================================
# Global scene state  (reset on each JSON load)
# ============================================================

_dwellings:       dict = {}   # d_id → {budget, x, y, floor, nh_id, mesh_idx}
_nh_dwelling_ids: dict = {}   # nh_id → [d_id, ...]
_roads_built:     set  = set()
_neighborhood_k:  int  = 8
_city_nx:         int  = 0
_city_ny:         int  = 0
_center_x:        float = 0.0
_center_y:        float = 0.0

_scheme: dict = {
    "attribute":  "budget",
    "min_value":  0.0,
    "max_value":  10.0,
    "color_low":  [0.15, 0.30, 0.85],
    "color_high": [0.85, 0.15, 0.15],
    "log_scale":  False,
}
_scheme_enabled: bool = True

# ============================================================
# Colour helpers  (identical to blender_vis.py)
# ============================================================

def _lerp(t: float, lo: list, hi: list) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(lo[i] + t * (hi[i] - lo[i]) for i in range(3))


def _scheme_value(d_id: int) -> float:
    entry = _dwellings.get(d_id)
    if entry is None:
        return 0.0
    attr = _scheme["attribute"]
    if attr == "budget":
        return entry["budget"]
    elif attr == "height":
        x, y = entry["x"], entry["y"]
        return float(sum(1 for e in _dwellings.values() if e["x"] == x and e["y"] == y))
    elif attr == "density":
        x, y, k = entry["x"], entry["y"], max(1, int(_neighborhood_k))
        ox, oy = (x // k) * k, (y // k) * k
        heights = {}
        for e in _dwellings.values():
            if ox <= e["x"] < ox + k and oy <= e["y"] < oy + k:
                pos = (e["x"], e["y"])
                heights[pos] = heights.get(pos, 0) + 1
        return float(sum(heights.values()) / len(heights)) if heights else 0.0
    return entry["budget"]


def _map_to_color(value: float) -> tuple:
    lo, hi = _scheme["min_value"], _scheme["max_value"]
    v = float(value)
    if _scheme["log_scale"] and v > 0 and lo > 0 and hi > lo:
        v, lo, hi = math.log(v), math.log(lo), math.log(hi)
    t = (v - lo) / (hi - lo) if hi != lo else 0.0
    return _lerp(t, _scheme["color_low"], _scheme["color_high"])


def _resolve_color(d_id: int) -> tuple:
    if not _scheme_enabled:
        return _GREY
    return _map_to_color(_scheme_value(d_id))

# ============================================================
# Scene helpers
# ============================================================

def _collection(name: str = "Dwellings") -> bpy.types.Collection:
    if name not in bpy.data.collections:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return bpy.data.collections[name]


def _neighborhood_id(x: int, y: int) -> int:
    k  = max(1, int(_neighborhood_k))
    nx = max(1, int(_city_nx))
    return (y // k) * nx + (x // k)

# ============================================================
# Shared dwelling material  (identical to blender_vis.py)
# ============================================================

def _get_dwelling_material() -> bpy.types.Material:
    mat = bpy.data.materials.get(_SHARED_MAT_NAME)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(_SHARED_MAT_NAME)
    mat.use_nodes    = True
    mat.blend_method = "BLEND"
    ng = mat.node_tree
    ng.nodes.clear()
    out  = ng.nodes.new("ShaderNodeOutputMaterial")
    bsdf = ng.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.55
    bsdf.inputs["Alpha"].default_value     = _DWELLING_ALPHA
    attr = ng.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "display_color"
    ng.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    ng.links.new(bsdf.outputs["BSDF"],  out.inputs["Surface"])
    return mat

# ============================================================
# Per-neighbourhood mesh  (identical to blender_vis.py)
# ============================================================

def _ensure_nh_obj(nh_id: int) -> bpy.types.Object:
    col  = _collection()
    name = f"{_NH_OBJ_PREFIX}{nh_id}"
    obj  = bpy.data.objects.get(name)
    if obj is None:
        mesh = bpy.data.meshes.new(f"{name}_Mesh")
        mesh.materials.append(_get_dwelling_material())
        obj = bpy.data.objects.new(name, mesh)
        col.objects.link(obj)
    return obj


def _rebuild_nh_mesh(nh_id: int):
    obj   = _ensure_nh_obj(nh_id)
    d_ids = _nh_dwelling_ids.get(nh_id, [])
    mesh  = obj.data
    n     = len(d_ids)
    mesh.clear_geometry()
    if n == 0:
        return

    offsets = np.empty((n, 3), dtype=np.float32)
    for i, d_id in enumerate(d_ids):
        e = _dwellings[d_id]
        offsets[i, 0] = float(e["x"])     - _center_x
        offsets[i, 1] = float(e["y"])     - _center_y
        offsets[i, 2] = float(e["floor"]) - 0.5

    verts = (_CUBE_VERTS_NP[np.newaxis] + offsets[:, np.newaxis]).reshape(n * 8, 3)
    vert_offsets = np.arange(n, dtype=np.int32) * 8
    loop_verts   = (
        _CUBE_LOOP_VERTS[np.newaxis] + vert_offsets[:, np.newaxis]
    ).reshape(n * 24)

    n_loops, n_faces = n * 24, n * 6
    mesh.vertices.add(n * 8)
    mesh.vertices.foreach_set("co", verts.ravel())
    mesh.loops.add(n_loops)
    mesh.loops.foreach_set("vertex_index", loop_verts)
    mesh.polygons.add(n_faces)
    mesh.polygons.foreach_set("loop_start", np.arange(0, n_loops, 4, dtype=np.int32))
    mesh.polygons.foreach_set("loop_total",  np.full(n_faces, 4, dtype=np.int32))
    mesh.update(calc_edges=True)

    if len(mesh.materials) == 0:
        mesh.materials.append(_get_dwelling_material())

    ca = mesh.color_attributes.get("display_color")
    if ca is not None:
        mesh.color_attributes.remove(ca)
    color_attr = mesh.color_attributes.new("display_color", "FLOAT_COLOR", "CORNER")

    colors = np.empty(n_loops * 4, dtype=np.float32)
    for i, d_id in enumerate(d_ids):
        c    = _resolve_color(d_id)
        rgba = np.array([c[0], c[1], c[2], 1.0], dtype=np.float32)
        colors[i * 96 : (i + 1) * 96] = np.tile(rgba, 24)

    color_attr.data.foreach_set("color", colors)
    mesh.update()

# ============================================================
# Roads  (identical to blender_vis.py)
# ============================================================

def _get_road_material() -> bpy.types.Material:
    mat = bpy.data.materials.get(_ROADS_MAT_NAME)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(_ROADS_MAT_NAME)
    mat.use_nodes = True
    ng = mat.node_tree
    ng.nodes.clear()
    out  = ng.nodes.new("ShaderNodeOutputMaterial")
    bsdf = ng.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value  = 0.9
    ng.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def _ensure_roads_obj() -> bpy.types.Object:
    obj = bpy.data.objects.get(_ROADS_OBJ_NAME)
    if obj is not None:
        return obj
    curve = bpy.data.curves.new(_ROADS_OBJ_NAME, "CURVE")
    curve.dimensions       = "3D"
    curve.bevel_depth      = _ROAD_BEVEL
    curve.bevel_resolution = 3
    curve.materials.append(_get_road_material())
    obj = bpy.data.objects.new(_ROADS_OBJ_NAME, curve)
    _collection("Roads").objects.link(obj)
    return obj


def _create_roads(roads: list):
    obj   = _ensure_roads_obj()
    curve = obj.data
    for r in roads:
        key = (min(r["nid_a"], r["nid_b"]), max(r["nid_a"], r["nid_b"]))
        if key in _roads_built:
            continue
        _roads_built.add(key)
        x_a = float(r["x_a"]) - _center_x
        y_a = float(r["y_a"]) - _center_y
        x_b = float(r["x_b"]) - _center_x
        y_b = float(r["y_b"]) - _center_y
        spline = curve.splines.new("POLY")
        spline.points.add(1)
        spline.points[0].co = (x_a, y_a, _ROAD_Z, 1.0)
        spline.points[1].co = (x_b, y_b, _ROAD_Z, 1.0)

# ============================================================
# Landscape
# ============================================================

def _create_landscape(size: float = 500.0):
    existing = bpy.data.objects.get("NIMBY_Landscape")
    if existing:
        bpy.data.objects.remove(existing, do_unlink=True)
    old_mat = bpy.data.materials.get("NIMBY_Landscape_Mat")
    if old_mat:
        bpy.data.materials.remove(old_mat)

    bpy.ops.mesh.primitive_plane_add(size=size, location=(0.0, 0.0, -0.05))
    obj      = bpy.context.active_object
    obj.name = "NIMBY_Landscape"
    mat = bpy.data.materials.new("NIMBY_Landscape_Mat")
    mat.use_nodes    = True
    mat.blend_method = "BLEND"
    mat.diffuse_color = (*_LANDSCAPE_COLOR, _LANDSCAPE_ALPHA)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*_LANDSCAPE_COLOR, 1.0)
        bsdf.inputs["Roughness"].default_value  = 1.0
        bsdf.inputs["Alpha"].default_value      = _LANDSCAPE_ALPHA
        spec = bsdf.inputs.get("Specular") or bsdf.inputs.get("Specular IOR Level")
        if spec:
            spec.default_value = 0.0
    obj.data.materials.clear()
    obj.data.materials.append(mat)

# ============================================================
# Full scene reset
# ============================================================

def _full_reset():
    global _dwellings, _nh_dwelling_ids, _roads_built
    _dwellings.clear()
    _nh_dwelling_ids.clear()
    _roads_built.clear()

    for obj in list(bpy.data.objects):
        if obj.name.startswith(_NH_OBJ_PREFIX):
            mesh = obj.data
            bpy.data.objects.remove(obj, do_unlink=True)
            if mesh is not None and mesh.users == 0:
                bpy.data.meshes.remove(mesh)
    obj = bpy.data.objects.get(_ROADS_OBJ_NAME)
    if obj:
        curve = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if curve is not None and curve.users == 0:
            bpy.data.curves.remove(curve)
    for mat_name in (_SHARED_MAT_NAME, _ROADS_MAT_NAME, "NIMBY_Landscape_Mat"):
        mat = bpy.data.materials.get(mat_name)
        if mat:
            bpy.data.materials.remove(mat)

# ============================================================
# Core loader  — reads one *_city.json and populates the scene
# ============================================================

def load_city_json(filepath: str, color_attr: str = "budget",
                   cs_min: float = 0.0, cs_max: float = 10.0):
    global _neighborhood_k, _city_nx, _city_ny, _center_x, _center_y
    global _scheme

    _full_reset()

    with open(filepath) as f:
        snap = json.load(f)

    cfg  = snap["city_config"]
    k    = int(cfg["k"])
    n_x  = int(cfg["n_x"])
    n_y  = int(cfg["n_y"])
    _neighborhood_k = k
    _city_nx        = n_x
    _city_ny        = n_y
    _center_x       = (n_x * k - 1) / 2.0
    _center_y       = (n_y * k - 1) / 2.0

    # Set colour scheme
    _scheme["attribute"] = color_attr
    _scheme["min_value"] = cs_min
    _scheme["max_value"] = cs_max

    # Auto-range for height and density if caller left defaults
    dwellings = snap.get("dwellings", [])
    if color_attr == "height" and cs_max == 10.0:
        # Compute max building height from dwelling data
        from collections import Counter
        ht = Counter((d["x"], d["y"]) for d in dwellings)
        _scheme["max_value"] = float(max(ht.values())) if ht else 10.0
    elif color_attr == "budget" and cs_max == 10.0:
        budgets = [d["budget"] for d in dwellings if d["budget"] > 0]
        _scheme["max_value"] = float(max(budgets)) if budgets else 10.0

    # Register dwellings in global state
    for d in dwellings:
        d_id  = int(d["id"])
        x, y  = int(d["x"]), int(d["y"])
        floor = int(d["floor"])
        nh_id = _neighborhood_id(x, y)
        ids   = _nh_dwelling_ids.setdefault(nh_id, [])
        _dwellings[d_id] = {
            "budget": float(d["budget"]),
            "x": x, "y": y, "floor": floor,
            "nh_id": nh_id, "mesh_idx": len(ids),
        }
        ids.append(d_id)

    # Build all neighbourhood meshes
    for nh_id in _nh_dwelling_ids:
        _rebuild_nh_mesh(nh_id)

    # Roads (only if present)
    roads = snap.get("roads", [])
    if roads:
        _create_roads(roads)

    # Landscape sized to city footprint
    footprint = max(n_x * k, n_y * k) * 1.5
    _create_landscape(footprint)

    return snap.get("run_id", os.path.basename(filepath))

# ============================================================
# Camera + lighting setup
# ============================================================

def _setup_camera_and_lights():
    """Angled overhead camera, single sun lamp."""
    city_w = _city_nx * _neighborhood_k
    city_h = _city_ny * _neighborhood_k
    cx = (_city_nx * _neighborhood_k - 1) / 2.0 - _center_x   # always 0 after centering
    cy = (_city_ny * _neighborhood_k - 1) / 2.0 - _center_y

    cam_dist = max(city_w, city_h) * 1.1

    # Remove default objects
    for name in ("Cube", "Light", "Camera",
                 "NIMBY_Camera", "NIMBY_Sun"):
        obj = bpy.data.objects.get(name)
        if obj:
            bpy.data.objects.remove(obj, do_unlink=True)

    # Sun
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 100))
    sun = bpy.context.active_object
    sun.name = "NIMBY_Sun"
    sun.data.energy = 3.0
    sun.data.angle  = math.radians(5)

    # Camera at 60° elevation, looking at city centre
    angle_elev = math.radians(60)
    cam_x = 0.0
    cam_y = -cam_dist * math.cos(angle_elev)
    cam_z =  cam_dist * math.sin(angle_elev)

    bpy.ops.object.camera_add(location=(cam_x, cam_y, cam_z))
    cam = bpy.context.active_object
    cam.name = "NIMBY_Camera"
    cam.rotation_euler = (math.radians(90) - angle_elev, 0, 0)
    cam.data.type = "PERSP"
    cam.data.lens = 35
    bpy.context.scene.camera = cam

# ============================================================
# Render helper
# ============================================================

def _render_to(filepath: str, resolution: int = 1920):
    scene = bpy.context.scene
    scene.render.engine              = "CYCLES"
    scene.cycles.samples             = 64
    scene.render.resolution_x        = resolution
    scene.render.resolution_y        = round(resolution * 0.75)
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath            = filepath
    bpy.ops.render.render(write_still=True)

# ============================================================
# Operators
# ============================================================

class SWEEP_OT_Load(bpy.types.Operator):
    bl_idname      = "wm.sweep_load"
    bl_label       = "Load City JSON"
    bl_description = "Load a sweep city snapshot and rebuild the scene"

    def execute(self, context):
        props    = context.scene.nimby_sweep
        filepath = bpy.path.abspath(props.json_path)
        if not os.path.isfile(filepath):
            self.report({"ERROR"}, f"File not found: {filepath}")
            return {"CANCELLED"}
        try:
            run_id = load_city_json(
                filepath,
                color_attr = props.color_attr,
                cs_min     = props.cs_min,
                cs_max     = props.cs_max,
            )
            _setup_camera_and_lights()
            self.report({"INFO"}, f"Loaded {run_id}")
        except Exception as e:
            self.report({"ERROR"}, str(e))
            print(traceback.format_exc())
        return {"FINISHED"}


class SWEEP_OT_Recolor(bpy.types.Operator):
    bl_idname      = "wm.sweep_recolor"
    bl_label       = "Recolor"
    bl_description = "Reapply current colour scheme to the loaded city"

    def execute(self, context):
        props = context.scene.nimby_sweep
        _scheme["attribute"] = props.color_attr
        _scheme["min_value"] = props.cs_min
        _scheme["max_value"] = props.cs_max
        for nh_id in list(_nh_dwelling_ids):
            _rebuild_nh_mesh(nh_id)
        return {"FINISHED"}


class SWEEP_OT_BatchRender(bpy.types.Operator):
    bl_idname      = "wm.sweep_batch_render"
    bl_label       = "Batch Render All"
    bl_description = "Load and render every *_city.json in the sweep directory"

    def execute(self, context):
        props      = context.scene.nimby_sweep
        sweep_dir  = bpy.path.abspath(props.sweep_dir)
        output_dir = bpy.path.abspath(props.render_output_dir)

        if not os.path.isdir(sweep_dir):
            self.report({"ERROR"}, f"Sweep dir not found: {sweep_dir}")
            return {"CANCELLED"}

        os.makedirs(output_dir, exist_ok=True)
        jsons = sorted(f for f in os.listdir(sweep_dir) if f.endswith("_city.json"))

        if not jsons:
            self.report({"WARNING"}, "No *_city.json files found")
            return {"CANCELLED"}

        for i, fname in enumerate(jsons):
            fpath  = os.path.join(sweep_dir, fname)
            run_id = fname.replace("_city.json", "")
            print(f"[SWEEP] {i+1}/{len(jsons)}: {run_id}")
            try:
                load_city_json(
                    fpath,
                    color_attr = props.color_attr,
                    cs_min     = props.cs_min,
                    cs_max     = props.cs_max,
                )
                _setup_camera_and_lights()
                out_path = os.path.join(output_dir, f"{run_id}_{props.color_attr}.png")
                _render_to(out_path, resolution=props.render_resolution)
                print(f"[SWEEP]   → {out_path}")
            except Exception as e:
                print(f"[SWEEP]   ERROR: {e}")
                print(traceback.format_exc())

        self.report({"INFO"}, f"Rendered {len(jsons)} cities → {output_dir}")
        return {"FINISHED"}

# ============================================================
# Properties
# ============================================================

class SweepLoaderProps(bpy.types.PropertyGroup):
    json_path: bpy.props.StringProperty(
        name="JSON file", subtype="FILE_PATH",
        description="Path to a single *_city.json snapshot",
        default="//sweep_results/",
    )
    sweep_dir: bpy.props.StringProperty(
        name="Sweep dir", subtype="DIR_PATH",
        description="Directory containing *_city.json files (batch render)",
        default="//sweep_results/",
    )
    render_output_dir: bpy.props.StringProperty(
        name="Output dir", subtype="DIR_PATH",
        description="Where batch renders are saved",
        default="//renders/",
    )
    render_resolution: bpy.props.IntProperty(
        name="Width (px)", default=1920, min=640, max=7680,
    )
    color_attr: bpy.props.EnumProperty(
        name="Color by",
        items=[
            ("budget",  "Budget",               "Occupant budget (blue=low, red=high)"),
            ("height",  "Building height",       "Number of floors"),
            ("density", "Neighbourhood density", "Mean height in neighbourhood"),
        ],
        default="height",
    )
    cs_min: bpy.props.FloatProperty(name="Min", default=0.0)
    cs_max: bpy.props.FloatProperty(
        name="Max", default=0.0,
        description="Set 0 to auto-range from data",
    )

# ============================================================
# Panel
# ============================================================

class SWEEP_PT_Panel(bpy.types.Panel):
    bl_label       = "NIMBY Sweep"
    bl_idname      = "SWEEP_PT_panel"
    bl_space_type  = "VIEW_3D"
    bl_region_type = "UI"
    bl_category    = "NIMBY Sweep"

    def draw(self, context):
        layout = self.layout
        props  = context.scene.nimby_sweep

        box = layout.box()
        box.label(text="Single City", icon="FILE")
        box.prop(props, "json_path")
        row = box.row(align=True)
        row.prop(props, "color_attr")
        row2 = box.row(align=True)
        row2.prop(props, "cs_min")
        row2.prop(props, "cs_max")
        box.operator("wm.sweep_load",    icon="IMPORT")
        box.operator("wm.sweep_recolor", icon="FILE_REFRESH")

        box = layout.box()
        box.label(text="Batch Render", icon="RENDER_ANIMATION")
        box.prop(props, "sweep_dir")
        box.prop(props, "render_output_dir")
        box.prop(props, "render_resolution")
        box.operator("wm.sweep_batch_render", icon="RENDER_STILL")

# ============================================================
# Registration
# ============================================================

_classes = [
    SweepLoaderProps,
    SWEEP_OT_Load,
    SWEEP_OT_Recolor,
    SWEEP_OT_BatchRender,
    SWEEP_PT_Panel,
]


def register():
    for cls in _classes:
        bpy.utils.register_class(cls)
    bpy.types.Scene.nimby_sweep = bpy.props.PointerProperty(type=SweepLoaderProps)


def unregister():
    for cls in reversed(_classes):
        bpy.utils.unregister_class(cls)
    del bpy.types.Scene.nimby_sweep


if __name__ == "__main__":
    # ── Headless batch render (command-line mode) ────────────────────────
    # blender --background --python blender_sweep_loader.py -- \
    #         --sweep_dir sweep_results --output_dir renders \
    #         --color_attr height
    import argparse

    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
        parser = argparse.ArgumentParser()
        parser.add_argument("--sweep_dir",   default="sweep_results")
        parser.add_argument("--output_dir",  default="renders")
        parser.add_argument("--color_attr",  default="height",
                            choices=["budget", "height", "density"])
        parser.add_argument("--cs_min",  type=float, default=0.0)
        parser.add_argument("--cs_max",  type=float, default=0.0)
        parser.add_argument("--resolution", type=int, default=1920)
        args = parser.parse_args(argv)

        os.makedirs(args.output_dir, exist_ok=True)
        jsons = sorted(f for f in os.listdir(args.sweep_dir)
                       if f.endswith("_city.json"))
        print(f"[SWEEP] Headless batch: {len(jsons)} cities → {args.output_dir}")
        for i, fname in enumerate(jsons):
            fpath  = os.path.join(args.sweep_dir, fname)
            run_id = fname.replace("_city.json", "")
            print(f"[SWEEP] {i+1}/{len(jsons)}: {run_id}")
            load_city_json(fpath, args.color_attr, args.cs_min, args.cs_max)
            _setup_camera_and_lights()
            out_path = os.path.join(args.output_dir,
                                    f"{run_id}_{args.color_attr}.png")
            _render_to(out_path, resolution=args.resolution)
    else:
        register()
