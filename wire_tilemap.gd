extends Area2D


var root_node: Node2D
var inside_area: bool


func _ready():
    root_node = get_node("/root/Node2D")
    inside_area = false


func _process(delta):
    if inside_area:
        if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
            return
        
        if root_node.is_in_placing_wire_state() and root_node.placing_wire_area == self.name:
            root_node.set_soft_wire_edge_to()
            
            var tile_map = null
            assert(self.name in ["Top", "Left", "Right"])
            if self.name == "Top":
                tile_map = root_node.wire_tile_map_top
            elif self.name == "Left":
                tile_map = root_node.wire_tile_map_left
            elif self.name == "Right":
                tile_map = root_node.wire_tile_map_right
            assert(tile_map != null)
            
            var cell = tile_map.local_to_map(tile_map.get_local_mouse_position())
            print(cell)
            var data = tile_map.get_cell_tile_data(0, cell)
            if data:
                if root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
                    tile_map.modulate.a = 0.25
        else:
            var wire_tilemaps: Node2D = get_node("WireTilemaps")
            for tile_map in wire_tilemaps.get_children():
                tile_map.modulate.a = 1.0
                var cell = tile_map.local_to_map(tile_map.get_local_mouse_position())
                var data = tile_map.get_cell_tile_data(0, cell)
                if data:
                    if not root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
                        tile_map.modulate.a = 0.25


func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
                return
            
            if not inside_area:
                return
            
            var wire_tilemaps: Node2D = get_node("WireTilemaps")
            for tile_map in wire_tilemaps.get_children():
                tile_map.modulate.a = 1.0
                var cell = tile_map.local_to_map(tile_map.get_local_mouse_position())
                var data = tile_map.get_cell_tile_data(0, cell)
                if data:
                    if not root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
                        root_node.remove_wire_edge(tile_map)


func _on_mouse_entered():
    inside_area = true
    root_node.wire_edge_to_soft = ""


func _on_mouse_exited():
    inside_area = false
