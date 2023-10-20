extends Area2D


var root_node: Node2D
var sprite: Sprite2D


# Called when the node enters the scene tree for the first time.
func _ready():
    root_node = get_node("/root/Node2D")
    sprite = get_node("Sprite2D")


func _on_mouse_entered():
    if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return
    
    if root_node.read_ignition_fuse(self.name):
        if not root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
            sprite.visible = true
            sprite.modulate.a = 0.5
    else:
        if root_node.get_current_edit_mode() == root_node.EditMode.WRITE and root_node.can_place_ignition_fuse(self.name):
            sprite.visible = true
            sprite.modulate.a = 0.5


func _on_mouse_exited():
    if not root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return
    
    sprite.modulate.a = 1
    sprite.visible = root_node.read_ignition_fuse(self.name)


func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            if root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
                var name: String = self.name
                root_node.edit_ignition_fuse(name, root_node.get_current_edit_mode() == root_node.EditMode.WRITE)
