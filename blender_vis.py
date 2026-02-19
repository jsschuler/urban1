"""
blender_vis.py — NIMBY ABM real-time visualizer for Blender

Install (run once in Blender's Python console):
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websocket-client"])

Load this file as a Blender script or add-on, then open the N-panel (View3D → N → NIMBY).
Press "Setup Scene" first, then "Start" to connect to the Julia WebSocket server.
"""

bl_info = {
    "name":     "NIMBY Visualizer",
    "blender":  (3, 0, 0),
    "category": "Interface",
}

import bpy
import json
import math
import queue
import threading

try:
    import websocket
except ImportError:
    import subprocess, sys
    subprocess.check_call([sys.executable, "-m", "pip", "install", "websocket-client"])
    import websocket

# ============================================================
# Constants
# ============================================================

_GREY            = (0.75, 0.75, 0.75)   # default dwelling colour
_LANDSCAPE_COLOR = (0.03, 0.14, 0.03)   # dark green ground plane

# ============================================================
# Global state  (module-level; survives operator re-runs)
# ============================================================

_msg_queue: queue.Queue = queue.Queue()
_ws: "websocket.WebSocketApp | None" = None
_ws_thread: "threading.Thread | None" = None

# Whether the colour scheme is active; False → all dwellings render as _GREY
_scheme_enabled: bool = False

# Colour scheme — kept in sync with Blender properties and Julia messages
_scheme: dict = {
    "attribute":  "budget",
    "min_value":  0.0,
    "max_value":  10.0,
    "color_low":  [0.15, 0.30, 0.85],
    "color_high": [0.85, 0.15, 0.15],
    "log_scale":  False,
}

# dwelling_id → {"obj": Object, "budget": float, "x": int, "y": int, "floor": int}
_dwellings: dict = {}

# ============================================================
# Colour helpers
# ============================================================

def _lerp(t: float, lo: list, hi: list) -> tuple:
    t = max(0.0, min(1.0, t))
    return tuple(lo[i] + t * (hi[i] - lo[i]) for i in range(3))


def _scheme_value(d_id: int) -> float:
    """Return the raw numeric value driving the colour for dwelling d_id."""
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
        # Mean building height inside the k×k neighbourhood block
        x, y, k = entry["x"], entry["y"], 8
        ox, oy = (x // k) * k, (y // k) * k
        heights, seen = {}, set()
        for e in _dwellings.values():
            if ox <= e["x"] < ox + k and oy <= e["y"] < oy + k:
                pos = (e["x"], e["y"])
                heights[pos] = heights.get(pos, 0) + 1
        return float(sum(heights.values()) / len(heights)) if heights else 0.0
    return entry["budget"]


def _map_to_color(value: float) -> tuple:
    """Map a raw value through the colour scheme gradient."""
    lo, hi = _scheme["min_value"], _scheme["max_value"]
    v = float(value)
    if _scheme["log_scale"] and v > 0 and lo > 0 and hi > lo:
        v, lo, hi = math.log(v), math.log(lo), math.log(hi)
    t = (v - lo) / (hi - lo) if hi != lo else 0.0
    return _lerp(t, _scheme["color_low"], _scheme["color_high"])


def _resolve_color(d_id: int) -> tuple:
    """Return the display colour for a dwelling — grey when scheme is off."""
    if not _scheme_enabled:
        return _GREY
    return _map_to_color(_scheme_value(d_id))

# ============================================================
# Scene helpers  (must be called from the main thread)
# ============================================================

def _collection(name: str = "Dwellings") -> bpy.types.Collection:
    if name not in bpy.data.collections:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return bpy.data.collections[name]


def _make_material(name: str, rgb: tuple) -> bpy.types.Material:
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value  = 0.55
    return mat


def _set_color(obj: bpy.types.Object, rgb: tuple):
    if obj.data.materials:
        bsdf = obj.data.materials[0].node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)


# ============================================================
# Landscape
# ============================================================

def create_landscape(size: float = 500.0):
    """
    Place a large flat plane at z = -0.05 so dwellings sit on top.
    The plane is offset so its corner aligns with the building grid origin (0, 0).
    Replaces any existing landscape.
    """
    existing = bpy.data.objects.get("NIMBY_Landscape")
    if existing:
        bpy.data.objects.remove(existing, do_unlink=True)
    if "NIMBY_Landscape_Mat" in bpy.data.materials:
        bpy.data.materials.remove(bpy.data.materials["NIMBY_Landscape_Mat"])

    bpy.ops.mesh.primitive_plane_add(
        size=size,
        location=(size / 2.0, size / 2.0, -0.05),
    )
    obj = bpy.context.active_object
    obj.name = "NIMBY_Landscape"

    mat = bpy.data.materials.new(name="NIMBY_Landscape_Mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*_LANDSCAPE_COLOR, 1.0)
        bsdf.inputs["Roughness"].default_value  = 1.0
        bsdf.inputs["Specular"].default_value   = 0.0

    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


# ============================================================
# Dwellings
# ============================================================

def create_dwelling(d_id: int, x: int, y: int, floor: int, budget: float):
    s       = 0.45          # half-width; leaves a small gap between cubes
    z0, z1  = float(floor - 1), float(floor)
    verts = [
        (x - s, y - s, z0), (x + s, y - s, z0),
        (x + s, y + s, z0), (x - s, y + s, z0),
        (x - s, y - s, z1), (x + s, y - s, z1),
        (x + s, y + s, z1), (x - s, y + s, z1),
    ]
    faces = [
        (0, 1, 2, 3), (4, 5, 6, 7),
        (0, 1, 5, 4), (2, 3, 7, 6),
        (0, 3, 7, 4), (1, 2, 6, 5),
    ]
    mesh = bpy.data.meshes.new(f"d_{d_id}")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(f"d_{d_id}", mesh)
    _collection().objects.link(obj)

    # Store entry before calling _resolve_color so _scheme_value can find it
    _dwellings[d_id] = {"obj": obj, "budget": budget, "x": x, "y": y, "floor": floor}
    obj.data.materials.append(_make_material(f"mat_d_{d_id}", _resolve_color(d_id)))


def update_budget(d_id: int, budget: float):
    entry = _dwellings.get(d_id)
    if entry is None:
        return
    entry["budget"] = budget
    # Only repaint immediately when budget is the active scheme attribute
    if _scheme_enabled and _scheme["attribute"] == "budget":
        _set_color(entry["obj"], _map_to_color(budget))


def recolor_all():
    """Recompute and apply colours for every dwelling using the current scheme."""
    for d_id, entry in _dwellings.items():
        _set_color(entry["obj"], _resolve_color(d_id))

# ============================================================
# Message dispatch
# ============================================================

def _handle(msg: dict):
    t = msg.get("type")

    if t == "new_dwellings":
        for d in msg["dwellings"]:
            create_dwelling(d["id"], d["x"], d["y"], d["floor"], d["budget"])

    elif t == "budget_updates":
        for u in msg["updates"]:
            update_budget(u["id"], u["budget"])

    elif t == "color_scheme":
        # A scheme pushed from Julia implicitly enables colour mode
        _scheme.update(msg["scheme"])
        props = bpy.context.scene.nimby_vis
        props["cs_attribute"] = _scheme["attribute"]
        props["cs_min"]       = float(_scheme["min_value"])
        props["cs_max"]       = float(_scheme["max_value"])
        props["cs_log_scale"] = bool(_scheme["log_scale"])
        if not props.cs_enabled:
            props.cs_enabled = True   # triggers _enabled_update → recolor_all
        else:
            recolor_all()

# ============================================================
# WebSocket background thread
# ============================================================

def _on_open(ws):
    print("[NIMBY] Connected to Julia visualizer")

def _on_message(ws, raw):
    try:
        _msg_queue.put(json.loads(raw))
    except Exception as e:
        print(f"[NIMBY] parse error: {e}")

def _on_error(ws, error):
    print(f"[NIMBY] error: {error}")

def _on_close(ws, code, reason):
    print(f"[NIMBY] disconnected (code={code})")


def _start_ws(url: str):
    global _ws, _ws_thread
    _ws = websocket.WebSocketApp(
        url,
        on_open=_on_open, on_message=_on_message,
        on_error=_on_error, on_close=_on_close,
    )
    _ws_thread = threading.Thread(target=_ws.run_forever, daemon=True)
    _ws_thread.start()


def _stop_ws():
    global _ws
    if _ws:
        _ws.close()
        _ws = None

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

        # Remove default objects that ship with a new Blender file
        for name in ("Cube", "Light", "Camera"):
            obj = bpy.data.objects.get(name)
            if obj:
                bpy.data.objects.remove(obj, do_unlink=True)

        # Sun lamp for clean overhead lighting
        bpy.ops.object.light_add(type="SUN", location=(0, 0, 100))
        sun = bpy.context.active_object
        sun.name = "NIMBY_Sun"
        sun.data.energy  = 3.0
        sun.data.angle   = math.radians(5)

        # Camera looking straight down from above the city centre
        half = props.landscape_size / 2.0
        bpy.ops.object.camera_add(location=(half, half, props.landscape_size * 0.8))
        cam = bpy.context.active_object
        cam.name = "NIMBY_Camera"
        cam.rotation_euler = (0, 0, 0)   # top-down
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
            changed = 0
            while changed < 500:
                try:
                    _handle(_msg_queue.get_nowait())
                    changed += 1
                except queue.Empty:
                    break
            if changed:
                for area in context.screen.areas:
                    if area.type == "VIEW_3D":
                        area.tag_redraw()
        return {"PASS_THROUGH"}

    def invoke(self, context, event):
        _start_ws(context.scene.nimby_vis.ws_url)
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
    def execute(self, context):
        _stop_ws()
        return {"FINISHED"}


class NIMBY_OT_Clear(bpy.types.Operator):
    bl_idname      = "wm.nimby_clear"
    bl_label       = "Clear Dwellings"
    bl_description = "Remove all dwelling cubes (landscape is kept)"
    def execute(self, context):
        for entry in _dwellings.values():
            bpy.data.objects.remove(entry["obj"], do_unlink=True)
        _dwellings.clear()
        return {"FINISHED"}


class NIMBY_OT_Recolor(bpy.types.Operator):
    bl_idname      = "wm.nimby_recolor"
    bl_label       = "Recolor All"
    bl_description = "Reapply colour scheme to all existing dwellings"
    def execute(self, context):
        recolor_all()
        return {"FINISHED"}

# ============================================================
# Properties
# ============================================================

def _enabled_update(self, context):
    global _scheme_enabled
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
    # --- connection ---
    ws_url: bpy.props.StringProperty(
        name="Server URL", default="ws://127.0.0.1:8765",
    )
    poll_interval: bpy.props.FloatProperty(
        name="Poll (s)", default=0.1, min=0.01, max=2.0,
    )
    # --- scene ---
    landscape_size: bpy.props.FloatProperty(
        name="Landscape size", default=500.0, min=10.0,
        description="Side length of the ground plane in Blender units",
    )
    # --- colour scheme ---
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
    cs_min: bpy.props.FloatProperty(
        name="Min", default=0.0, update=_scheme_update,
    )
    cs_max: bpy.props.FloatProperty(
        name="Max", default=10.0, update=_scheme_update,
    )
    cs_color_low: bpy.props.FloatVectorProperty(
        name="Low colour",  subtype="COLOR", size=3, min=0.0, max=1.0,
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

        # Scene setup
        box = layout.box()
        box.label(text="Scene", icon="WORLD")
        box.prop(props, "landscape_size")
        box.operator("wm.nimby_setup", icon="SCENE_DATA")

        # Connection
        box = layout.box()
        box.label(text="Connection", icon="URL")
        box.prop(props, "ws_url")
        box.prop(props, "poll_interval")
        row = box.row(align=True)
        row.operator("wm.nimby_start", icon="PLAY")
        row.operator("wm.nimby_stop",  icon="PAUSE")
        box.operator("wm.nimby_clear", icon="TRASH")

        # Colour scheme
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
