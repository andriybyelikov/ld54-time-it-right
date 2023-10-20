extends Node2D


enum EditMode {
    WRITE,
    DELETE,
}

enum EditTarget {
    EXPLOSIVES,
    FUSES,
}


# Impulse to apply a certain amount of time after the start of the simulation
class TimedImpulse:
    var time: float
    var impulse: Vector2

    func _init(time: float, impulse: Vector2):
        self.time = time
        self.impulse = impulse
    
    func _to_string():
        return "TimedImpulse(" + str(time) + ", " + str(impulse) + ")"


class WireEdge:
    var from: String
    var to: String
    var time: float
    var tile_map: TileMap
    var path: PackedVector2Array

    func _init(from: String, to: String, time: float, tile_map: TileMap):
        self.from = from
        self.to = to
        self.time = time
        self.tile_map = tile_map


# UI Editing State
var editing_mode_button_group: ButtonGroup
var palette_button_group: ButtonGroup

# Wire TileMap TileSet
@export var tile_set: TileSet

# Payload RigidBody Template
var payload_template: RigidBody2D

# AStarGrid2D Template
var astar_grid_template: AStarGrid2D


# Wiring State
var wire_edge_from: String
var wire_edge_to: String

# Used for making the arrow face the hovered explosive
var wire_edge_to_soft: String
var soft_path: PackedVector2Array

# used to prevent wire tangling
var soft_path_without_last_segment: PackedVector2Array

# keep track of which area the player is currently placing the wire in
var placing_wire_area: String

# path anchor points
var anchor_points: Array[Vector2i]


# Pathfinding data structures for computing the wiring paths
var astar_grid_top: AStarGrid2D
var astar_grid_left: AStarGrid2D
var astar_grid_right: AStarGrid2D

# Wire TileMaps for wire placement visual aid
var wire_tile_map_top: TileMap
var wire_tile_map_left: TileMap
var wire_tile_map_right: TileMap

# Timed Impulse Sequence Computation Input
var explosives_left: Array[int]
var explosives_right: Array[int]
var explosives_bottom: Array[int]
var wire_edges: Array[WireEdge]
var ignition_side: String

# Simulation Input
var timed_impulse_sequence: Array[TimedImpulse]

# Simulation Control Flags
var need_reset: bool
var need_compute_impulse_sequence: bool
var do_integration: bool

# Simulation Tracking
var time_accumulator: float
var impulse_counter: int


func init_payload_rigid_body_template():
    var shape: RectangleShape2D = RectangleShape2D.new()
    shape.size = Vector2(14, 16)

    var collision_shape: CollisionShape2D = CollisionShape2D.new()
    collision_shape.shape = shape
    collision_shape.scale = Vector2(1.01, 1.01)

    var sprite2d: Sprite2D = Sprite2D.new()
    sprite2d.texture = load("res://tileset.png")
    sprite2d.region_rect = Rect2i(0, 0, 16, 16)
    sprite2d.region_enabled = true
    sprite2d.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    
    payload_template = RigidBody2D.new()
    payload_template.name = "Payload"
    payload_template.lock_rotation = true
    payload_template.global_position = Vector2(0, -8)
    payload_template.add_child(collision_shape)
    payload_template.add_child(sprite2d)


func create_astar_grid(region: Rect2i):
    var astar_grid = AStarGrid2D.new()
    astar_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
    astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
    astar_grid.cell_size = Vector2i(1, 1)
    astar_grid.region = region
    astar_grid.update()
    return astar_grid


func init_simulation():
    need_compute_impulse_sequence = false
    do_integration = false

    # init simulation tracking
    time_accumulator = 0.0
    impulse_counter = 0
    
    if has_node("World/Payload"):
        get_node("World").remove_child(get_node("World/Payload"))
    get_node("World").add_child(payload_template.duplicate())


func reset_astar_grids():
    astar_grid_top = create_astar_grid(Rect2i(0, 0, 14, 6))
    astar_grid_left = create_astar_grid(Rect2i(0, 0, 6, 10))
    astar_grid_right = create_astar_grid(Rect2i(0, 0, 6, 10))


func _ready():
    editing_mode_button_group = get_node("/root/Node2D/Camera2D/UI/Editing/Pencil").button_group
    palette_button_group = get_node("/root/Node2D/Camera2D/UI/Editing/Explosive300").button_group

    init_payload_rigid_body_template()


    wire_edge_from = ""
    wire_edge_to = ""
    wire_edge_to_soft = ""
    placing_wire_area = ""
    anchor_points = []


    reset_astar_grids()


    wire_tile_map_top = null
    wire_tile_map_left = null
    wire_tile_map_right = null


    explosives_left = [0, 0, 0]
    explosives_right = [0, 0, 0]
    explosives_bottom = [0, 0, 0, 0, 0]
    wire_edges = []
    ignition_side = ""


    timed_impulse_sequence = []


    need_reset = true


func _process(delta):
    if need_reset:
        need_reset = false
        init_simulation()

    if need_compute_impulse_sequence:
        need_compute_impulse_sequence = false
        compute_impulse_sequence()
        print(timed_impulse_sequence)

    if do_integration:
        time_accumulator += delta
        if impulse_counter < len(timed_impulse_sequence):
            var timed_impulse: TimedImpulse = timed_impulse_sequence[impulse_counter]
            if time_accumulator >= timed_impulse.time:
                if has_node("World/Payload"): # prevents crashing in case the level is completed before all impulses have been applied
                    var payload: RigidBody2D = get_node("World/Payload")
                    payload.apply_impulse(timed_impulse.impulse)
                impulse_counter += 1




func compute_explosive_impulse(name: String) -> Vector2:
    var pipe: String = name.substr(0, 1)
    assert(pipe in ["L", "R", "B"])

    var number: int = int(name.substr(1, 1))
    var index: int = number - 1

    var magnitude: int = 0
    var direction: Vector2 = Vector2.ZERO

    if pipe == "L":
        magnitude = explosives_left[index]
        direction = Vector2.RIGHT
    elif pipe == "R":
        magnitude = explosives_right[index]
        direction = Vector2.LEFT
    elif pipe == "B":
        magnitude = explosives_bottom[index]
        direction = Vector2.UP

    assert(magnitude > 0 and direction != Vector2.ZERO)
    return magnitude * direction


func compute_impulse_sequence():
    timed_impulse_sequence = []

    if ignition_side == "":
        return

    var first_explosive: String = ignition_side + "1"
    var time_accum: float = 0
    var explosive_cur: String = first_explosive
    var wire_edges_dup: Array[WireEdge] = wire_edges.duplicate()
    while not wire_edges_dup.is_empty() and explosive_cur != "":
        # search for target explosive
        var found: bool = false
        for wire_edge in wire_edges_dup:
            if wire_edge.from.substr(0, 2) == explosive_cur: # found
                found = true
                var time: float = time_accum
                var impulse: Vector2 = compute_explosive_impulse(explosive_cur)
                timed_impulse_sequence.append(TimedImpulse.new(time, impulse))
                
                # set next explosive to visit, remove current as visited,
                # add fuse delay to time accumulator
                explosive_cur = wire_edge.to.substr(0, 2)
                wire_edges_dup.erase(wire_edge)
                time_accum += wire_edge.time
                break
        # not found
        if not found:
            explosive_cur = ""
    
    # last explosive
    if explosive_cur != "":
        var time: float = time_accum
        var impulse: Vector2 = compute_explosive_impulse(explosive_cur)
        timed_impulse_sequence.append(TimedImpulse.new(time, impulse))




func get_current_edit_mode() -> EditMode:
    var name: String = editing_mode_button_group.get_pressed_button().name
    assert(name in ["Pencil", "Eraser"])

    if name == "Pencil":
        return EditMode.WRITE
    else: # name == "Eraser"
        return EditMode.DELETE


func get_current_edit_target() -> EditTarget:
    var name: String = palette_button_group.get_pressed_button().name
    assert(name.begins_with("Explosive") or name.begins_with("Fuse"))

    if name.begins_with("Explosive"):
        return EditTarget.EXPLOSIVES
    else: # name.begins_with("Fuse")
        return EditTarget.FUSES


func is_in_placing_wire_state() -> bool:
    return wire_edge_from != "" and wire_edge_to == ""




func write_explosive(name: String, value: int):
    if get_current_edit_mode() == EditMode.DELETE:
        value = 0
    
    var number: int = int(name.substr(1, 1))
    var index: int = number - 1
    
    if name.begins_with("L"):
        if not value:
            pass
        explosives_left[index] = value
    elif name.begins_with("R"):
        if not value:
            pass
        explosives_right[index] = value
    elif name.begins_with("B"):
        if not value:
            pass
        explosives_bottom[index] = value
    


func read_explosive(name: String) -> int:
    var pipe: String = name.substr(0, 1)
    assert(pipe in ["L", "R", "B"])

    var number: int = int(name.substr(1, 1))
    var index: int = number - 1

    if pipe == "L":
        return explosives_left[index]
    elif pipe == "R":
        return explosives_right[index]
    else: # pipe == "B"
        return explosives_bottom[index]




func can_place_ignition_fuse(name: String) -> bool:
    return (
        (name == "L" and explosives_left[0] > 0) or
        (name == "R" and explosives_right[0] > 0) or
        (name == "B" and explosives_bottom[0] > 0)
    )
    
func edit_ignition_fuse(name: String, value: bool):
    # graphics
    if can_place_ignition_fuse(name) or not get_current_edit_mode() == EditMode.WRITE:
        if ignition_side != "":
            var sprite_old: Sprite2D = get_node("Camera2D/UI/Wiring/IgnitionSlots/" + ignition_side + "/Sprite2D")
            sprite_old.visible = not value
        var sprite_new: Sprite2D = get_node("Camera2D/UI/Wiring/IgnitionSlots/" + name + "/Sprite2D")
        sprite_new.visible = value

    # logic
    if value:
        if can_place_ignition_fuse(name):
            ignition_side = name
    else:
        if ignition_side == name:
            ignition_side = ""


func remove_ignition_fuse():
    # hide ignition side sprite and reset model
    if ignition_side != "": # prevent crash in case ignition side is not set
        get_node("Camera2D/UI/Wiring/IgnitionSlots/" + ignition_side + "/Sprite2D").visible = false
        ignition_side = ""

func read_ignition_fuse(name: String) -> bool:
    return ignition_side == name




func set_wire_edge_from(node_name: String):
    wire_edge_from = node_name
    
    # build TileMap
    if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
        wire_tile_map_top = TileMap.new()
        wire_tile_map_top.tile_set = tile_set
        wire_tile_map_top.translate(Vector2i(-7 * 16, -3 * 16))
        get_node("Camera2D/UI/Wiring/ValidWireAreas/Top/WireTilemaps").add_child(wire_tile_map_top)
        placing_wire_area = "Top"
    elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
        wire_tile_map_left = TileMap.new()
        wire_tile_map_left.tile_set = tile_set
        wire_tile_map_left.translate(Vector2i(-3 * 16, -5 * 16))
        get_node("Camera2D/UI/Wiring/ValidWireAreas/Left/WireTilemaps").add_child(wire_tile_map_left)
        placing_wire_area = "Left"
    elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
        wire_tile_map_right = TileMap.new()
        wire_tile_map_right.tile_set = tile_set
        wire_tile_map_right.translate(Vector2i(-3 * 16, -5 * 16))
        get_node("Camera2D/UI/Wiring/ValidWireAreas/Right/WireTilemaps").add_child(wire_tile_map_right)
        placing_wire_area = "Right"


func set_wire_edge_arrow_tile():
    if len(soft_path) == 0: # no idea
        return
    
    var palette_button_name: String = palette_button_group.get_pressed_button().name
    var fuse_type: String = palette_button_name.replace("Fuse0", "")
    var fuse_value_string: String = "0." + fuse_type
    var fuse_value: float = float(fuse_value_string)
    
    var edge: WireEdge = null
    var wire_tile_map = null
    var node_name = wire_edge_from
    if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
        wire_tile_map = wire_tile_map_top
    elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
        wire_tile_map = wire_tile_map_left
    elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
        wire_tile_map = wire_tile_map_right
    
    if wire_edge_to_soft == "":
        edge = WireEdge.new(wire_edge_from, wire_edge_to, fuse_value, wire_tile_map)
    else:
        edge = WireEdge.new(wire_edge_from, wire_edge_to_soft, fuse_value, wire_tile_map)
    
    var current_cell: Vector2i = soft_path[len(soft_path) - 1]
    var previous_cell: Vector2i = soft_path[len(soft_path) - 2]
    var entering_direction: Vector2i = current_cell - previous_cell
    var exiting_direction: Vector2i = Vector2i.ZERO
    
    var e = edge
    
    if e.to[0] == 'L' or e.to[0] == 'R':
        # up or down
        if e.to[2] == 'T':
            exiting_direction = Vector2i.DOWN
        else: # e.to[2] == 'B'
            exiting_direction = Vector2i.UP
    else: # e.to[0] == 'B'
        # left or right
        if e.to[3] == 'L':
            exiting_direction = Vector2i.RIGHT
        else: # e.to[3] == 'R':
            exiting_direction = Vector2i.LEFT
    
    var tile_base: Vector2i = Vector2i.ZERO
    var color_base: Vector2i = Vector2i.ZERO
    if entering_direction == exiting_direction:
        if e.time == 0.50:
            color_base = Vector2i(0, 0)
        elif e.time == 0.25:
            color_base = Vector2i(2, 0)
        elif e.time == 0.10:
            color_base = Vector2i(4, 0)
        elif e.time == 0.01:
            color_base = Vector2i(6, 0)
    else:
        if e.time == 0.50:
            color_base = Vector2i(0, 0)
        elif e.time == 0.25:
            color_base = Vector2i(0, 2)
        elif e.time == 0.10:
            color_base = Vector2i(0, 4)
        elif e.time == 0.01:
            color_base = Vector2i(0, 6)
    
    var arrow_offset = Vector2i.ZERO
    
    if entering_direction == Vector2i.UP and exiting_direction == Vector2i.UP:
        tile_base = Vector2i(20, 6)
        arrow_offset = Vector2i(0, 0)
    elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.RIGHT:
        tile_base = Vector2i(20, 6)
        arrow_offset = Vector2i(1, 0)
    elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.LEFT:
        tile_base = Vector2i(20, 6)
        arrow_offset = Vector2i(0, 1)
    elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.DOWN:
        tile_base = Vector2i(20, 6)
        arrow_offset = Vector2i(1, 1)
    
    elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.DOWN:
        tile_base = Vector2i(28, 0)
        arrow_offset = Vector2i(0, 0)
    elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.RIGHT:
        tile_base = Vector2i(28, 0)
        arrow_offset = Vector2i(0, 1)
    elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.UP:
        tile_base = Vector2i(28, 0)
        arrow_offset = Vector2i(1, 1)
    elif entering_direction == Vector2i.UP and exiting_direction == Vector2i.LEFT:
        tile_base = Vector2i(28, 0)
        arrow_offset = Vector2i(1, 0)
    
    elif entering_direction == Vector2i.UP and exiting_direction == Vector2i.RIGHT:
        tile_base = Vector2i(30, 0)
        arrow_offset = Vector2i(0, 0)
    elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.DOWN:
        tile_base = Vector2i(30, 0)
        arrow_offset = Vector2i(1, 0)
    elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.LEFT:
        tile_base = Vector2i(30, 0)
        arrow_offset = Vector2i(1, 1)
    elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.UP:
        tile_base = Vector2i(30, 0)
        arrow_offset = Vector2i(0, 1)
    
    tile_base += color_base
    tile_base += arrow_offset
    e.tile_map.set_cell(0, current_cell, 0, tile_base)


func set_soft_wire_edge_to():
    var palette_button_name: String = palette_button_group.get_pressed_button().name
    var fuse_type: String = palette_button_name.replace("Fuse0", "")
    var fuse_value_string: String = "0." + fuse_type
    var fuse_value: float = float(fuse_value_string)
    
    var wire_tile_map = null
    var node_name = wire_edge_from
    if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
        wire_tile_map = wire_tile_map_top
    elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
        wire_tile_map = wire_tile_map_left
    elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
        wire_tile_map = wire_tile_map_right
    
    var edge: WireEdge = WireEdge.new(wire_edge_from, wire_edge_to, fuse_value, wire_tile_map)
    var target: Vector2i = wire_tile_map.local_to_map(wire_tile_map.get_local_mouse_position())
    wire_tile_map.clear()
    add_wire_edge(edge, true, target)


func add_wire_path_anchor_point_if_possible(point: Vector2i):
    if point not in anchor_points:
        anchor_points.append(point)


func explosive_has_input_wire(name: String) -> bool:
    if name[1] == '1' and ignition_side == str(name[0]):
        return true
    
    var found: bool = false
    for e in wire_edges:
        if e.to.substr(0, 2) == name:
            found = true
            break
    return found


func explosive_has_output_wire(name: String) -> bool:
    var found: bool = false
    for e in wire_edges:
        if e.from.substr(0, 2) == name:
            found = true
            break
    return found

func explosive_has_exhaust_blocked_by_another_explosive(name: String) -> bool:
        var number: int = int(name[1])
        var index: int = number - 1
        
        var found: bool = false
        assert(name[0] in ['L', 'R', 'B'])
        for i in range(0, index):
            var adjacent_name: String = name[0] + str(i + 1)
            # NOTE: the directly adjacent explosive may still not have the output connected
            if not (explosive_has_input_wire(adjacent_name) and (i < index or explosive_has_output_wire(adjacent_name))):
                print(adjacent_name + " still not connected!")
                found = true
                break
        return found


func add_fuse_edge_node(node_name: String):
    if wire_edge_from == "":
        # prevent connecting explosives when
        # connecting an output but the wire has no input
        if not explosive_has_input_wire(node_name.substr(0, 2)):
            return
        
        # prevent connecting explosives when
        # connecting an output but the wire already has an output
        if explosive_has_output_wire(node_name.substr(0, 2)):
            return
        
        # prevent connecting explosives when
        # an adjacent explosive closer to the exhaust is not connected yet
        if explosive_has_exhaust_blocked_by_another_explosive(node_name.substr(0, 2)):
            return
        
        set_wire_edge_from(node_name)
    else:
        # prevent connecting explosives when
        # connecting an input but the wire already has an input
        if explosive_has_input_wire(node_name.substr(0, 2)):
            return
        
        # prevent connecting explosives when
        # an adjacent explosive closer to the exhaust is not connected yet
        if explosive_has_exhaust_blocked_by_another_explosive(node_name.substr(0, 2)):
            return
        
        
        wire_edge_to = node_name
        
        var palette_button_name: String = palette_button_group.get_pressed_button().name
        var fuse_type: String = palette_button_name.replace("Fuse0", "")
        var fuse_value_string: String = "0." + fuse_type
        var fuse_value: float = float(fuse_value_string)
        
        var wire_tile_map = null
        if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
            wire_tile_map = wire_tile_map_top
        elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
            wire_tile_map = wire_tile_map_left
        elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
            wire_tile_map = wire_tile_map_right
        assert(wire_tile_map != null)
        
        var edge: WireEdge = WireEdge.new(wire_edge_from, wire_edge_to, fuse_value, wire_tile_map)
        wire_tile_map.modulate.a = 1.0
        
        
        
#        print("Adding WireEdge: " + wire_edge_from + " to " + wire_edge_to + " @ " + fuse_value_string + "s")
        wire_edges.append(edge)
        wire_tile_map.clear()
        add_wire_edge(edge, false, Vector2i.ZERO)
        
        wire_edge_from = ""
        wire_edge_to = ""
        wire_edge_to_soft = ""
        placing_wire_area = ""
        anchor_points = []
        
        wire_tile_map = null


func cancel_wire_placing():
    if placing_wire_area == "Top":
        wire_tile_map_top.queue_free()
        wire_tile_map_top = null
    elif placing_wire_area == "Left":
        wire_tile_map_left.queue_free()
        wire_tile_map_left = null
    elif placing_wire_area == "Right":
        wire_tile_map_right.queue_free()
        wire_tile_map_right = null
    
    wire_edge_from = ""
    wire_edge_to = ""
    wire_edge_to_soft = ""
    placing_wire_area = ""
    anchor_points = []

# maps node name to A* grid point
func compute_point_from_name(name: String):
    var x: int
    var y: int
    
    if name[0] in ['L', 'R']:
        if name[2] == 'T':
            y = 6 - 1
            if name[0] == 'L':
                x = 0
                x += (int(name[1]) - 1) * 2
                if name[3] == 'L':
                    x += 0
                else: # name[3] == 'R'
                    x += 1
            else: # name[0] == 'R'
                x = 12
                x -= (int(name[1]) - 1) * 2
                if name[3] == 'L':
                    x += 0
                else:
                    x += 1
        else: # name[2] == 'B'
            y = 0
            if name[0] == 'L':
                x = 0
                x += (int(name[1]) - 1) * 2
                if name[3] == 'L':
                    x += 0
                else: # name[3] == 'R'
                    x += 1
            else: # name[0] == 'R'
                x = 4
                x -= (int(name[1]) - 1) * 2
                if name[3] == 'L':
                    x += 0
                else:
                    x += 1
    else: # name[0] == 'B'
        if name[3] == 'L':
            x = 6 - 1
        else: # name[3] == 'R'
            x = 0
        
        y = 8
        y -= (int(name[1]) - 1) * 2
        if name[2] == 'T':
            y += 0
        else: # name[2] == 'B'
            y += 1
    
    return Vector2i(x, y)


func add_wire_edge(e: WireEdge, soft_mode: bool, soft_target: Vector2i):
    # prepare A* points
    var origin: Vector2i = compute_point_from_name(e.from)
    var target: Vector2i
    if soft_mode:
        target = soft_target
    else:
        target = compute_point_from_name(e.to)
    
    if soft_mode and origin == target:
        return
    
    var astar_grid = null
    var node_name = e.from
    if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
        astar_grid = astar_grid_top
    elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
        astar_grid = astar_grid_left
    elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
        astar_grid = astar_grid_right
    
    # reset soft wire placement solid cells
    for cell in soft_path_without_last_segment:
        astar_grid.set_point_solid(cell, false)
    
    # compute combined path passing through anchor points
    var id_path: PackedVector2Array = PackedVector2Array()
    for anchor_point in anchor_points:
        var id_subpath: PackedVector2Array = astar_grid.get_id_path(origin, anchor_point)
        id_subpath.remove_at(id_subpath.size() - 1)
        for cell in id_subpath:
            astar_grid.set_point_solid(cell, true)
        id_path.append_array(id_subpath)
        origin = anchor_point
    
    # save id_path without last segment to reset the solid cells
    # in the next soft wire placement computation
    soft_path_without_last_segment = id_path
    
    # final segment
    id_path.append_array(astar_grid.get_id_path(origin, target))
    
    if not soft_mode:
        e.path = id_path
    else:
        soft_path = id_path
    
    for i in len(id_path):
        # we need to compute both the entering direction and the exiting direction
        # to determine which tile to use
        # entering direction = current_cell - previous_cell
        # exiting direction = next_cell - current_cell
        # only the origin cell entering direction and the target cell exiting direction
        # are computed differently
        
        var current_cell: Vector2i = id_path[i]
        if not soft_mode:
            astar_grid.set_point_solid(current_cell, true)
        
        var entering_direction: Vector2i = Vector2i.ZERO
        var exiting_direction: Vector2i = Vector2i.ZERO
        
        if i == 0: # origin cell
            if e.from[0] == 'L' or e.from[0] == 'R':
                # up or down
                if e.from[2] == 'T':
                    entering_direction = Vector2i.UP
                else: # e.from[2] == 'B'
                    entering_direction = Vector2i.DOWN
            else: # e.from[0] == 'B'
                # left or right
                if e.from[3] == 'L':
                    entering_direction = Vector2i.LEFT
                else: # e.from[2] == 'R':
                    entering_direction = Vector2i.RIGHT
            
            var next_cell: Vector2i = id_path[i + 1]
            exiting_direction = next_cell - current_cell
        elif i == len(id_path) - 1 and not soft_mode: # target cell
            var previous_cell: Vector2i = id_path[i - 1]
            entering_direction = current_cell - previous_cell
            
            if e.to[0] == 'L' or e.to[0] == 'R':
                # up or down
                if e.to[2] == 'T':
                    exiting_direction = Vector2i.DOWN
                else: # e.to[2] == 'B'
                    exiting_direction = Vector2i.UP
            else: # e.to[0] == 'B'
                # left or right
                if e.to[3] == 'L':
                    exiting_direction = Vector2i.RIGHT
                else: # e.to[3] == 'R':
                    exiting_direction = Vector2i.LEFT
        else:
            var previous_cell: Vector2i = id_path[i - 1]
            entering_direction = current_cell - previous_cell
            var next_cell: Vector2i
            if len(id_path) > i + 1:
                next_cell = id_path[i + 1]
                exiting_direction = next_cell - current_cell
            else:
                exiting_direction = entering_direction
        
        # map entering and exiting directions to tile
        var tile_x: int = 0
        var tile_y: int = 0
        if entering_direction == exiting_direction:
            if entering_direction.x != 0:
                tile_x = 1
                tile_y = 0
            else:
                tile_x = 0
                tile_y = 1
        else:
            if (
                (entering_direction == Vector2i.UP and exiting_direction == Vector2i.RIGHT) or
                (entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.DOWN)
            ):
                tile_x = 0
                tile_y = 0
            elif (
                (entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.DOWN) or
                (entering_direction == Vector2i.UP and exiting_direction == Vector2i.LEFT)
            ):
                tile_x = 2
                tile_y = 0
            elif (
                (entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.LEFT) or
                (entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.UP)
            ):
                tile_x = 2
                tile_y = 2
            elif (
                (entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.UP) or
                (entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.RIGHT)
            ):
                tile_x = 0
                tile_y = 2
        
        if i == len(id_path) - 1: # target cell
            var tile_base: Vector2i = Vector2i.ZERO
            
            var color_base: Vector2i = Vector2i.ZERO
            if entering_direction == exiting_direction:
                if e.time == 0.50:
                    color_base = Vector2i(0, 0)
                elif e.time == 0.25:
                    color_base = Vector2i(2, 0)
                elif e.time == 0.10:
                    color_base = Vector2i(4, 0)
                elif e.time == 0.01:
                    color_base = Vector2i(6, 0)
            else:
                if e.time == 0.50:
                    color_base = Vector2i(0, 0)
                elif e.time == 0.25:
                    color_base = Vector2i(0, 2)
                elif e.time == 0.10:
                    color_base = Vector2i(0, 4)
                elif e.time == 0.01:
                    color_base = Vector2i(0, 6)
            
            var arrow_offset = Vector2i.ZERO
            
            if entering_direction == Vector2i.UP and exiting_direction == Vector2i.UP:
                tile_base = Vector2i(20, 6)
                arrow_offset = Vector2i(0, 0)
            elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.RIGHT:
                tile_base = Vector2i(20, 6)
                arrow_offset = Vector2i(1, 0)
            elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.LEFT:
                tile_base = Vector2i(20, 6)
                arrow_offset = Vector2i(0, 1)
            elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.DOWN:
                tile_base = Vector2i(20, 6)
                arrow_offset = Vector2i(1, 1)
            
            elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.DOWN:
                tile_base = Vector2i(28, 0)
                arrow_offset = Vector2i(0, 0)
            elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.RIGHT:
                tile_base = Vector2i(28, 0)
                arrow_offset = Vector2i(0, 1)
            elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.UP:
                tile_base = Vector2i(28, 0)
                arrow_offset = Vector2i(1, 1)
            elif entering_direction == Vector2i.UP and exiting_direction == Vector2i.LEFT:
                tile_base = Vector2i(28, 0)
                arrow_offset = Vector2i(1, 0)
            
            elif entering_direction == Vector2i.UP and exiting_direction == Vector2i.RIGHT:
                tile_base = Vector2i(30, 0)
                arrow_offset = Vector2i(0, 0)
            elif entering_direction == Vector2i.RIGHT and exiting_direction == Vector2i.DOWN:
                tile_base = Vector2i(30, 0)
                arrow_offset = Vector2i(1, 0)
            elif entering_direction == Vector2i.DOWN and exiting_direction == Vector2i.LEFT:
                tile_base = Vector2i(30, 0)
                arrow_offset = Vector2i(1, 1)
            elif entering_direction == Vector2i.LEFT and exiting_direction == Vector2i.UP:
                tile_base = Vector2i(30, 0)
                arrow_offset = Vector2i(0, 1)
            
            tile_base += color_base
            tile_base += arrow_offset
            e.tile_map.set_cell(0, current_cell, 0, tile_base)
        else:
            var tile_base: Vector2i = Vector2i(20, 0)
            var color_base: Vector2i = Vector2i.ZERO
            if e.time == 0.50:
                color_base = Vector2i(0, 0)
            elif e.time == 0.25:
                color_base = Vector2i(3, 0)
            elif e.time == 0.10:
                color_base = Vector2i(0, 3)
            elif e.time == 0.01:
                color_base = Vector2i(3, 3)
            tile_base += color_base
            tile_base.x += tile_x
            tile_base.y += tile_y
            e.tile_map.set_cell(0, current_cell, 0, tile_base)


func remove_wire_edge(tile_map: TileMap):
    # find WireEdge by tile_map
    var wire_edge: WireEdge = null
    for e in wire_edges:
        if e.tile_map == tile_map:
            wire_edge = e
    
    var astar_grid = null
    var node_name = wire_edge.from
    if (node_name[0] == 'L' or node_name[0] == 'R') and node_name[2] == 'T':
        astar_grid = astar_grid_top
    elif (node_name[0] == 'L' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'L'):
        astar_grid = astar_grid_left
    elif (node_name[0] == 'R' and node_name[2] == 'B') or (node_name[0] == 'B' and node_name[3] == 'R'):
        astar_grid = astar_grid_right

    # unset solid grids in astar_grid
    for p in wire_edge.path:
        astar_grid.set_point_solid(p, false)
    
    # free tileset
    tile_map.queue_free()
    
    # remove wire_edge from array
    wire_edges.erase(wire_edge)




func _on_area_2d_body_entered(body: PhysicsBody2D):
    if body.get_name() == "Payload":
        var payload: Node2D = get_node("World/Payload")
        payload.visible = false
        var dialog: AcceptDialog = get_node("Camera2D/AcceptDialog")
        dialog.visible = true


func _on_ignite_button_pressed():
    get_node("Camera2D/UI/IgniteButton").visible = false
    get_node("Camera2D/UI/ResetButton").visible = true
    get_node("Camera2D/UI/Editing").visible = false
    
    need_compute_impulse_sequence = true
    do_integration = true
    


func _on_reset_button_pressed():
    get_node("Camera2D/UI/IgniteButton").visible = true
    get_node("Camera2D/UI/ResetButton").visible = false
    get_node("Camera2D/UI/Editing").visible = true
    need_reset = true


func _on_clear_pressed():
    # hide all non-zero explosive sprites and reset model
    
    for i in len(explosives_left):
        var value: int = explosives_left[i]
        if value > 0:
            explosives_left[i] = 0
            get_node("Camera2D/UI/Wiring/ExplosiveSlots/L" + str(i + 1) + "/Sprite2D").visible = false
    
    for i in len(explosives_right):
        var value: int = explosives_right[i]
        if value > 0:
            explosives_right[i] = 0
            get_node("Camera2D/UI/Wiring/ExplosiveSlots/R" + str(i + 1) + "/Sprite2D").visible = false
    
    for i in len(explosives_bottom):
        var value: int = explosives_bottom[i]
        if value > 0:
            explosives_bottom[i] = 0
            get_node("Camera2D/UI/Wiring/ExplosiveSlots/B" + str(i + 1) + "/Sprite2D").visible = false
    
    # reset A* grids
    reset_astar_grids()
    
    # remove all wire tilemaps
    for e in wire_edges:
        e.tile_map.queue_free()
    wire_edges = []
    
    # remove ignition fuse
    remove_ignition_fuse()
