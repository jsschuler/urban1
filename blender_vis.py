"""
blender_vis.py — NIMBY ABM real-time visualizer for Blender

Install (run once in Blender's Python console):
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websocket-client"])

Load this file as a Blender script or add-on, then open the N-panel (View3D → N → NIMBY).
Press "Setup Scene" first, then "Start" to connect to the Julia WebSocket server.

Rendering approach
──────────────────
One mesh object per neighbourhood (NIMBY_NH_<id>).  Each dwelling is 6 quad faces
(8 vertices, 24 loops) added directly to that mesh.  A FLOAT_COLOR CORNER attribute
named "display_color" carries one RGBA colour per loop; all 24 loops of a dwelling
share the same colour so each cube face is uniformly coloured.

The shared material reads "display_color" via ShaderNodeAttribute (attribute_type
GEOMETRY), which is the standard, version-stable way to read per-face-corner
attributes from a mesh — no instancing tricks required.
"""

bl_info = {
    "name":     "NIMBY Visualizer",
    "blender":  (3, 2, 0),   # FLOAT_COLOR color_attributes requires Blender 3.2+
    "category": "Interface",
}

import bpy
import json
import math
import queue
import threading
import traceback
import numpy as np

try:
    import websocket
except ImportError:
    import sys, site
    user_site = site.getusersitepackages()
    if user_site not in sys.path:
        sys.path.append(user_site)
    try:
        import websocket
    except ImportError:
        import subprocess, ensurepip
        ensurepip.bootstrap()
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websocket-client"])
        import websocket

websocket.enableTrace(False)

# ============================================================
# Constants
# ============================================================

_GREY            = (0.75, 0.75, 0.75)
_LANDSCAPE_COLOR = (0.04, 0.24, 0.06)

_NH_OBJ_PREFIX  = "NIMBY_NH_"
_SHARED_MAT_NAME = "NIMBY_DwellingMat"

# Template cube: 0.9 × 0.9 × 1.0 units, centred at origin.
# 8 vertices, 6 quad faces (24 loops total per dwelling).
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

# Precomputed numpy templates for fast mesh construction
_CUBE_VERTS_NP   = np.array(_CUBE_VERTS, dtype=np.float32)            # (8, 3)
_CUBE_LOOP_VERTS = np.array(                                           # (24,)
    [vi for face in _CUBE_FACES for vi in face], dtype=np.int32
)

# ============================================================
# Global state
# ============================================================

_msg_queue: queue.Queue = queue.Queue()
_ws: "websocket.WebSocketApp | None" = None
_ws_thread: "threading.Thread | None" = None

_scheme_enabled: bool = False

_scheme: dict = {
    "attribute":  "budget",
    "min_value":  0.0,
    "max_value":  10.0,
    "color_low":  [0.15, 0.30, 0.85],
    "color_high": [0.85, 0.15, 0.15],
    "log_scale":  False,
}

_neighborhood_k: int = 8
_city_nx: int = 0
_city_ny: int = 0
_center_x: float = 0.0
_center_y: float = 0.0

# Neighbourhoods queued for a mesh rebuild; processed in the modal timer.
_pending_rebuild: set = set()
# Max neighbourhood mesh rebuilds per timer tick — limits freeze duration.
_MAX_REBUILDS_PER_TICK = 4

# dwelling_id → {"budget", "x", "y", "floor", "nh_id", "mesh_idx"}
# mesh_idx is the 0-based position of this dwelling within its neighbourhood's
# mesh — used to compute its loop range: [mesh_idx*24, mesh_idx*24+24).
_dwellings: dict = {}

# nh_id → [d_id, d_id, ...] insertion-order list; index = mesh_idx
_nh_dwelling_ids: dict = {}

# ============================================================
# Colour helpers
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
# Shared material — reads display_color from mesh geometry
# ============================================================

def _get_dwelling_material() -> bpy.types.Material:
    """
    One shared Principled BSDF material used by every neighbourhood mesh.
    Reads the 'display_color' FLOAT_COLOR CORNER attribute directly from the
    mesh geometry (attribute_type GEOMETRY), giving each dwelling cube its
    own colour without needing per-object materials or instancing tricks.
    """
    mat = bpy.data.materials.get(_SHARED_MAT_NAME)
    if mat is not None:
        return mat

    mat = bpy.data.materials.new(_SHARED_MAT_NAME)
    mat.use_nodes = True
    ng = mat.node_tree
    ng.nodes.clear()

    out  = ng.nodes.new("ShaderNodeOutputMaterial")
    bsdf = ng.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.55

    attr = ng.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "display_color"
    # attribute_type defaults to "GEOMETRY" — reads from the mesh's own
    # per-face-corner attribute data, which is what we populate below.

    ng.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    ng.links.new(bsdf.outputs["BSDF"],  out.inputs["Surface"])
    return mat

# ============================================================
# Per-neighbourhood mesh objects
# ============================================================

def _ensure_nh_obj(nh_id: int) -> bpy.types.Object:
    """
    Return (creating if needed) the mesh object for neighbourhood nh_id.
    The mesh directly contains cube geometry; geometry and colour attributes
    are rebuilt by _rebuild_nh_mesh whenever dwellings are added.
    """
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
    """
    Rebuild the neighbourhood mesh using numpy arrays + foreach_set for speed.
    Called from the modal timer (capped per tick) rather than inline in
    create_dwellings_batch, so multiple incoming batches for the same
    neighbourhood collapse into a single rebuild.
    """
    obj   = _ensure_nh_obj(nh_id)
    d_ids = _nh_dwelling_ids.get(nh_id, [])
    mesh  = obj.data
    n     = len(d_ids)

    mesh.clear_geometry()
    if n == 0:
        return

    # ── Geometry ──────────────────────────────────────────────────────────
    # offsets: (n, 3) — one (cx, cy, cz) per dwelling
    offsets = np.empty((n, 3), dtype=np.float32)
    for i, d_id in enumerate(d_ids):
        e = _dwellings[d_id]
        offsets[i, 0] = float(e["x"])     - _center_x
        offsets[i, 1] = float(e["y"])     - _center_y
        offsets[i, 2] = float(e["floor"]) - 0.5

    # verts: (n*8, 3) via broadcasting — no Python loop over vertices
    verts = (_CUBE_VERTS_NP[np.newaxis] + offsets[:, np.newaxis]).reshape(n * 8, 3)

    # loop vertex indices: dwelling i shifts all 24 refs by i*8
    vert_offsets = np.arange(n, dtype=np.int32) * 8          # (n,)
    loop_verts   = (
        _CUBE_LOOP_VERTS[np.newaxis] + vert_offsets[:, np.newaxis]
    ).reshape(n * 24)                                          # (n*24,)

    n_loops = n * 24
    n_faces = n * 6

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

    # ── Colour attribute ───────────────────────────────────────────────────
    ca = mesh.color_attributes.get("display_color")
    if ca is not None:
        mesh.color_attributes.remove(ca)
    color_attr = mesh.color_attributes.new("display_color", "FLOAT_COLOR", "CORNER")

    # Build flat RGBA array (n*24*4 floats) — one numpy tile per dwelling
    colors = np.empty(n_loops * 4, dtype=np.float32)
    for i, d_id in enumerate(d_ids):
        c    = _resolve_color(d_id)
        rgba = np.array([c[0], c[1], c[2], 1.0], dtype=np.float32)
        colors[i * 96 : (i + 1) * 96] = np.tile(rgba, 24)   # 24 loops × 4 floats

    color_attr.data.foreach_set("color", colors)
    mesh.update()

# ============================================================
# Landscape
# ============================================================

def create_landscape(size: float = 500.0):
    existing = bpy.data.objects.get("NIMBY_Landscape")
    if existing:
        bpy.data.objects.remove(existing, do_unlink=True)
    if "NIMBY_Landscape_Mat" in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials["NIMBY_Landscape_Mat"])

    bpy.ops.mesh.primitive_plane_add(size=size, location=(0.0, 0.0, -0.05))
    obj = bpy.context.active_object
    obj.name = "NIMBY_Landscape"

    mat = bpy.data.materials.new(name="NIMBY_Landscape_Mat")
    mat.use_nodes = True
    mat.diffuse_color = (*_LANDSCAPE_COLOR, 1.0)
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*_LANDSCAPE_COLOR, 1.0)
        bsdf.inputs["Roughness"].default_value  = 1.0
        spec = bsdf.inputs.get("Specular") or bsdf.inputs.get("Specular IOR Level")
        if spec:
            spec.default_value = 0.0

    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj

# ============================================================
# Dwellings
# ============================================================

def create_dwellings_batch(items: list):
    """
    Register new dwellings in the internal data structures and queue their
    neighbourhoods for a mesh rebuild.  The actual rebuild is deferred to the
    modal timer (_pending_rebuild), capped at _MAX_REBUILDS_PER_TICK per tick,
    so multiple consecutive batches for the same neighbourhood collapse into a
    single rebuild and never block the UI for more than a few milliseconds.
    """
    for d in items:
        d_id = d["id"]
        if d_id in _dwellings:
            continue
        x, y, floor, budget = d["x"], d["y"], d["floor"], d["budget"]
        nh_id = _neighborhood_id(x, y)

        ids      = _nh_dwelling_ids.setdefault(nh_id, [])
        mesh_idx = len(ids)
        ids.append(d_id)

        _dwellings[d_id] = {
            "budget": budget, "x": x, "y": y, "floor": floor,
            "nh_id": nh_id, "mesh_idx": mesh_idx,
        }
        _pending_rebuild.add(nh_id)


def reset_dwellings():
    _dwellings.clear()
    _nh_dwelling_ids.clear()
    _pending_rebuild.clear()
    for obj in bpy.data.objects:
        if obj.name.startswith(_NH_OBJ_PREFIX) and obj.type == "MESH":
            mesh = obj.data
            mesh.clear_geometry()
            ca = mesh.color_attributes.get("display_color")
            if ca is not None:
                mesh.color_attributes.remove(ca)


def update_budget(d_id: int, budget: float):
    entry = _dwellings.get(d_id)
    if entry is None:
        return
    entry["budget"] = budget
    mesh_idx = entry.get("mesh_idx", -1)
    if mesh_idx < 0:
        return
    obj = bpy.data.objects.get(f"{_NH_OBJ_PREFIX}{entry['nh_id']}")
    if obj is None:
        return
    color_attr = obj.data.color_attributes.get("display_color")
    if color_attr is None:
        return
    color = _resolve_color(d_id)
    rgba  = (*color, 1.0)
    base  = mesh_idx * _LOOPS_PER_DWELLING
    for li in range(base, base + _LOOPS_PER_DWELLING):
        color_attr.data[li].color = rgba
    obj.data.update()


def recolor_all():
    """Recompute and write display_color for every dwelling."""
    dirty: set = set()
    for d_id, entry in _dwellings.items():
        mesh_idx = entry.get("mesh_idx", -1)
        if mesh_idx < 0:
            continue
        obj = bpy.data.objects.get(f"{_NH_OBJ_PREFIX}{entry['nh_id']}")
        if obj is None:
            continue
        color_attr = obj.data.color_attributes.get("display_color")
        if color_attr is None:
            continue
        color = _resolve_color(d_id)
        rgba  = (*color, 1.0)
        base  = mesh_idx * _LOOPS_PER_DWELLING
        for li in range(base, base + _LOOPS_PER_DWELLING):
            color_attr.data[li].color = rgba
        dirty.add(obj.data)
    for mesh in dirty:
        mesh.update()

# ============================================================
# Message dispatch
# ============================================================

def _handle(msg: dict):
    global _neighborhood_k, _city_nx, _city_ny, _center_x, _center_y  # noqa: PLW0603
    t = msg.get("type")

    if t == "city_config":
        k   = msg.get("k")
        n_x = msg.get("n_x")
        n_y = msg.get("n_y")
        if isinstance(k, int) and k > 0:
            _neighborhood_k = k
            if isinstance(n_x, int) and isinstance(n_y, int) and n_x > 0 and n_y > 0:
                _city_nx  = n_x
                _city_ny  = n_y
                _center_x = (n_x * k - 1) / 2.0
                _center_y = (n_y * k - 1) / 2.0
            else:
                _center_x = (k - 1) / 2.0
                _center_y = (k - 1) / 2.0

    elif t == "new_dwellings":
        create_dwellings_batch(msg["dwellings"])

    elif t == "budget_updates":
        for u in msg["updates"]:
            update_budget(u["id"], u["budget"])

    elif t == "reset":
        reset_dwellings()

    elif t == "color_scheme":
        _scheme.update(msg["scheme"])
        props = bpy.context.scene.nimby_vis
        props.cs_attribute = _scheme["attribute"]
        props.cs_min       = float(_scheme["min_value"])
        props.cs_max       = float(_scheme["max_value"])
        props.cs_log_scale = bool(_scheme["log_scale"])
        if not props.cs_enabled:
            props.cs_enabled = True   # triggers _enabled_update → recolor_all
        else:
            recolor_all()

# ============================================================
# WebSocket background thread
# ============================================================

def _on_open(_ws):
    print("[NIMBY] Connected to Julia visualizer")

def _on_message(_ws, raw):
    try:
        _msg_queue.put(json.loads(raw))
    except Exception as e:
        print(f"[NIMBY] parse error: {e}")
        print(traceback.format_exc())

def _on_error(_ws, error):
    print(f"[NIMBY] error ({type(error).__name__}): {error!r}")

def _on_close(_ws, _code, _reason):
    print(f"[NIMBY] disconnected (code={_code}, reason={_reason!r})")


def _start_ws(url: str):
    global _ws, _ws_thread
    if _ws is not None:
        print("[NIMBY] existing websocket detected; closing before reconnect")
        _stop_ws()
    _ws = websocket.WebSocketApp(
        url,
        on_open=_on_open, on_message=_on_message,
        on_error=_on_error, on_close=_on_close,
    )
    def _runner():
        try:
            _ws.run_forever()
        except Exception as e:
            print(f"[NIMBY] run_forever crashed: {e!r}")
            print(traceback.format_exc())
    _ws_thread = threading.Thread(target=_runner, daemon=True)
    _ws_thread.start()
    print(f"[NIMBY] websocket thread started (alive={_ws_thread.is_alive()})")


def _stop_ws():
    global _ws, _ws_thread
    if _ws:
        _ws.close()
        _ws = None
    if _ws_thread and _ws_thread.is_alive():
        _ws_thread.join(timeout=1.0)
    _ws_thread = None

# ============================================================
# Operators
# ============================================================

class NIMBY_OT_Setup(bpy.types.Operator):
    bl_idname      = "wm.nimby_setup"
    bl_label       = "Setup Scene"
    bl_description = "Create the landscape and reset lighting for the NIMBY model"

    def execute(self, context):
        props = context.scene.nimby_vis
        create_landscape(props.landscape_size)

        for name in ("Cube", "Light", "Camera"):
            obj = bpy.data.objects.get(name)
            if obj:
                bpy.data.objects.remove(obj, do_unlink=True)

        bpy.ops.object.light_add(type="SUN", location=(0, 0, 100))
        sun = bpy.context.active_object
        sun.name = "NIMBY_Sun"
        sun.data.energy = 3.0
        sun.data.angle  = math.radians(5)

        bpy.ops.object.camera_add(location=(0.0, 0.0, props.landscape_size * 0.8))
        cam = bpy.context.active_object
        cam.name = "NIMBY_Camera"
        cam.rotation_euler = (0, 0, 0)
        context.scene.camera = cam

        self.report({"INFO"}, f"Scene ready — landscape {props.landscape_size:.0f}×{props.landscape_size:.0f}")
        return {"FINISHED"}


class NIMBY_OT_Start(bpy.types.Operator):
    bl_idname      = "wm.nimby_start"
    bl_label       = "Start"
    bl_description = "Connect to the Julia NIMBY model"
    _timer = None

    def modal(self, context, event):
        if event.type == "TIMER":
            # Drain incoming messages (data updates only — no mesh rebuilds)
            changed = 0
            while changed < 500:
                try:
                    msg = _msg_queue.get_nowait()
                except queue.Empty:
                    break
                try:
                    _handle(msg)
                    changed += 1
                except Exception as e:
                    print(f"[NIMBY] handle error: {e!r} | msg={msg}")
                    print(traceback.format_exc())

            # Rebuild pending neighbourhood meshes, capped per tick to avoid
            # long freezes.  Remaining entries are processed on the next tick.
            rebuilt = 0
            for nh_id in list(_pending_rebuild):
                if rebuilt >= _MAX_REBUILDS_PER_TICK:
                    break
                _rebuild_nh_mesh(nh_id)
                _pending_rebuild.discard(nh_id)
                rebuilt += 1

            if changed or rebuilt:
                for area in context.screen.areas:
                    if area.type == "VIEW_3D":
                        area.tag_redraw()
        return {"PASS_THROUGH"}

    def invoke(self, context, _event):
        if _ws_thread is not None and _ws_thread.is_alive():
            self.report({"WARNING"}, "WebSocket is already running")
            return {"CANCELLED"}
        url = context.scene.nimby_vis.ws_url
        print(f"[NIMBY] starting websocket to {url}")
        _start_ws(url)
        wm = context.window_manager
        self._timer = wm.event_timer_add(
            context.scene.nimby_vis.poll_interval, window=context.window
        )
        wm.modal_handler_add(self)
        return {"RUNNING_MODAL"}

    def cancel(self, context):
        context.window_manager.event_timer_remove(self._timer)
        _stop_ws()


class NIMBY_OT_Stop(bpy.types.Operator):
    bl_idname = "wm.nimby_stop"
    bl_label  = "Stop"
    def execute(self, _context):
        _stop_ws()
        return {"FINISHED"}


class NIMBY_OT_Clear(bpy.types.Operator):
    bl_idname      = "wm.nimby_clear"
    bl_label       = "Clear Dwellings"
    bl_description = "Remove all dwelling cubes (landscape is kept)"
    def execute(self, _context):
        reset_dwellings()
        return {"FINISHED"}


class NIMBY_OT_Recolor(bpy.types.Operator):
    bl_idname      = "wm.nimby_recolor"
    bl_label       = "Recolor All"
    bl_description = "Reapply colour scheme to all existing dwellings"
    def execute(self, _context):
        recolor_all()
        return {"FINISHED"}


class NIMBY_OT_Reset(bpy.types.Operator):
    bl_idname      = "wm.nimby_reset"
    bl_label       = "Reset"
    bl_description = "Clear all dwellings in Blender and request a full model reset from Julia"
    def execute(self, _context):
        reset_dwellings()
        if _ws is not None:
            try:
                _ws.send(json.dumps({"type": "reset_request"}))
            except Exception as e:
                self.report({"WARNING"}, f"Could not send reset to Julia: {e}")
        return {"FINISHED"}

# ============================================================
# Properties
# ============================================================

def _enabled_update(self, context):
    global _scheme_enabled  # noqa: PLW0603
    _scheme_enabled = context.scene.nimby_vis.cs_enabled
    recolor_all()


def _scheme_update(self, context):
    p = context.scene.nimby_vis
    _scheme.update({
        "attribute":  p.cs_attribute,
        "min_value":  p.cs_min,
        "max_value":  p.cs_max,
        "color_low":  list(p.cs_color_low),
        "color_high": list(p.cs_color_high),
        "log_scale":  p.cs_log_scale,
    })
    if _scheme_enabled:
        recolor_all()


class NIMBYVisProps(bpy.types.PropertyGroup):
    ws_url: bpy.props.StringProperty(
        name="Server URL", default="ws://127.0.0.1:8765",
    )
    poll_interval: bpy.props.FloatProperty(
        name="Poll (s)", default=0.1, min=0.01, max=2.0,
    )
    landscape_size: bpy.props.FloatProperty(
        name="Landscape size", default=500.0, min=10.0,
        description="Side length of the ground plane in Blender units",
    )
    cs_enabled: bpy.props.BoolProperty(
        name="Enable colour scheme",
        description="When off, all dwellings render as light grey",
        default=False,
        update=_enabled_update,
    )
    cs_attribute: bpy.props.EnumProperty(
        name="Color by",
        items=[
            ("budget",  "Budget",               "Occupant budget (0 = vacant)"),
            ("height",  "Building height",       "Number of floors in building"),
            ("density", "Neighbourhood density", "Mean height in neighbourhood"),
        ],
        default="budget",
        update=_scheme_update,
    )
    cs_min: bpy.props.FloatProperty(name="Min", default=0.0, update=_scheme_update)
    cs_max: bpy.props.FloatProperty(name="Max", default=10.0, update=_scheme_update)
    cs_color_low: bpy.props.FloatVectorProperty(
        name="Low colour", subtype="COLOR", size=3, min=0.0, max=1.0,
        default=(0.15, 0.30, 0.85), update=_scheme_update,
    )
    cs_color_high: bpy.props.FloatVectorProperty(
        name="High colour", subtype="COLOR", size=3, min=0.0, max=1.0,
        default=(0.85, 0.15, 0.15), update=_scheme_update,
    )
    cs_log_scale: bpy.props.BoolProperty(
        name="Log scale", default=False, update=_scheme_update,
    )

# ============================================================
# Panel
# ============================================================

class NIMBY_PT_Panel(bpy.types.Panel):
    bl_label       = "NIMBY Visualizer"
    bl_idname      = "NIMBY_PT_panel"
    bl_space_type  = "VIEW_3D"
    bl_region_type = "UI"
    bl_category    = "NIMBY"

    def draw(self, context):
        layout = self.layout
        props  = context.scene.nimby_vis

        box = layout.box()
        box.label(text="Scene", icon="WORLD")
        box.prop(props, "landscape_size")
        box.operator("wm.nimby_setup", icon="SCENE_DATA")

        box = layout.box()
        box.label(text="Connection", icon="URL")
        box.prop(props, "ws_url")
        box.prop(props, "poll_interval")
        row = box.row(align=True)
        row.operator("wm.nimby_start", icon="PLAY")
        row.operator("wm.nimby_stop",  icon="PAUSE")
        box.operator("wm.nimby_clear", icon="TRASH")
        box.operator("wm.nimby_reset", icon="LOOP_BACK")

        box = layout.box()
        box.label(text="Colour Scheme", icon="MATERIAL")
        box.prop(props, "cs_enabled", toggle=True)
        col = box.column()
        col.enabled = props.cs_enabled
        col.prop(props, "cs_attribute")
        row = col.row(align=True)
        row.prop(props, "cs_min")
        row.prop(props, "cs_max")
        col.prop(props, "cs_color_low")
        col.prop(props, "cs_color_high")
        col.prop(props, "cs_log_scale")
        col.operator("wm.nimby_recolor", icon="FILE_REFRESH")

# ============================================================
# Registration
# ============================================================

_classes = [
    NIMBYVisProps,
    NIMBY_OT_Setup,
    NIMBY_OT_Start,
    NIMBY_OT_Stop,
    NIMBY_OT_Clear,
    NIMBY_OT_Recolor,
    NIMBY_OT_Reset,
    NIMBY_PT_Panel,
]

def register():
    for cls in _classes:
        bpy.utils.register_class(cls)
    bpy.types.Scene.nimby_vis = bpy.props.PointerProperty(type=NIMBYVisProps)

def unregister():
    for cls in reversed(_classes):
        bpy.utils.unregister_class(cls)
    del bpy.types.Scene.nimby_vis

if __name__ == "__main__":
    register()
