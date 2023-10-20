extends Area2D

var root_node: Node2D
var palette_button_group: ButtonGroup
var sprite: Sprite2D

func _ready():
    root_node = get_node("/root/Node2D")
    palette_button_group = get_node("/root/Node2D/Camera2D/UI/Editing/Explosive300").button_group
    
    sprite = self.get_node("Sprite2D")
    sprite.texture = load("res://tileset.png")
    sprite.region_enabled = true
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _on_mouse_entered():
    if root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return

    var value: int = root_node.read_explosive(self.name)
    if value > 0 and root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
        sprite.visible = true
        sprite.modulate.a = 1
        return

    
    sprite.visible = true
    if root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
        sprite.modulate.a = 0.75
    else:
        if value == 0:
            sprite.modulate.a = 0
        else:
            sprite.modulate.a = 0.5
    var pressed_button: BaseButton = palette_button_group.get_pressed_button()
    var selected_name: String = pressed_button.name
    if selected_name.begins_with("Explosive"):
        var orient_offset: int = 64
        if self.name.begins_with("B"):
            orient_offset = 0
        var type_offset: int = 0
        
        if value == 0:
            if selected_name.contains("600"):
                type_offset = 32
        elif value == 300:
            type_offset = 0
        elif value == 600:
            type_offset = 32
        var x: int = orient_offset + type_offset
        sprite.region_rect = Rect2i(x, 64, 32, 32)
    else:
        sprite.visible = false


func _on_mouse_exited():
    if root_node.get_current_edit_target() == root_node.EditTarget.FUSES:
        return

    sprite.visible = root_node.read_explosive(self.name) > 0
    sprite.modulate.a = 1


func _on_input_event(viewport, event, shape_idx):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            var pressed_button: BaseButton = palette_button_group.get_pressed_button()
            var selected_name: String = pressed_button.name
            if selected_name.begins_with("Explosive"):
                if root_node.read_explosive(self.name) == 0 or not root_node.get_current_edit_mode() == root_node.EditMode.WRITE:
                    var value: int = int(selected_name.replace("Explosive", ""))
                    root_node.write_explosive(self.name, value)
