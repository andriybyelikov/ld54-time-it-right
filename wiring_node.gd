extends Area2D


var root_node: Node2D


# Called when the node enters the scene tree for the first time.
func _ready():
    root_node = get_node("/root/Node2D")


func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
                if root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
                    root_node.add_fuse_edge_node(self.name)


func _on_mouse_entered():
    if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return
    
    if root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
        if root_node.is_in_placing_wire_state():
            if root_node.wire_edge_to_soft != self.name:
                root_node.wire_edge_to_soft = self.name
                root_node.set_wire_edge_arrow_tile()


func _on_mouse_exited():
    if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return
