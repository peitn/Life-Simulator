extends VBoxContainer
## Read-only presentation of a draft. Own world, visual instance, materials and rig.
## No SimAgent, game clock, private state or multiplayer calls belong here.
const Visual := preload("res://scripts/sim/sim_visual.gd")
const CharacterData := preload("res://scripts/character/character_data.gd")

var viewport: SubViewport
var visual: Node3D
var camera: Camera3D
var _image: TextureRect
var _snapshot: Dictionary = {}
var _angle := 0.0
var _height := 1.8
var _model_note: Label

func _ready() -> void:
    name = "CharacterPreview"
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _image = TextureRect.new()
    _image.custom_minimum_size = Vector2(0, 220)
    _image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _image.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_image)
    viewport = SubViewport.new()
    viewport.name = "DraftWorld"
    viewport.size = Vector2i(360, 280)
    viewport.own_world_3d = true
    viewport.world_3d = World3D.new()
    viewport.handle_input_locally = false
    viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
    add_child(viewport)
    _image.texture = viewport.get_texture()
    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color(0.075, 0.09, 0.12)
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color(0.8, 0.85, 1.0)
    environment.ambient_light_energy = 0.65
    world_environment.environment = environment
    viewport.add_child(world_environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-35, -25, 0)
    light.light_energy = 1.5
    viewport.add_child(light)
    visual = Visual.new()
    visual.name = "DraftVisual"
    visual.expressions_enabled = false
    viewport.add_child(visual)
    visual.process_mode = Node.PROCESS_MODE_DISABLED
    # SimVisual's gameplay overlays are deliberately absent in a dressing preview.
    visual.get("_gem").hide()
    visual.get("_label").hide()
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.current = true
    viewport.add_child(camera)
    _frame_character()
    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    add_child(buttons)
    for entry in [["Vlevo", -PI / 4], ["Zepředu", 0.0], ["Vpravo", PI / 4]]:
        var button := Button.new()
        button.text = entry[0]
        button.pressed.connect(_turn.bind(float(entry[1])))
        buttons.add_child(button)
    _model_note = Label.new()
    _model_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _model_note.text = "Náhled návrhu" if visual.uses_model() else "Náhled návrhu — zjednodušený model (assety nedostupné)"
    add_child(_model_note)

func show_draft(data: Dictionary) -> void:
    var cd := CharacterData.new()
    cd.set_from_dict(data)
    var snapshot := cd.public_snapshot()
    if snapshot == _snapshot:
        return
    _snapshot = snapshot.duplicate(true)
    visual.apply_look(snapshot)
    _height = float(snapshot.get("body", {}).get("height_cm", 180.0)) / 100.0
    _frame_character()

func _frame_character() -> void:
    camera.size = maxf(2.5, _height * 1.4)
    camera.position = Vector3(0, _height * 0.52, 4)
    camera.look_at(Vector3(0, _height * 0.52, 0))

func _turn(delta: float) -> void:
    _angle = 0.0 if is_zero_approx(delta) else wrapf(_angle + delta, -PI, PI)
    visual.rotation.y = _angle

func public_snapshot() -> Dictionary:
    return _snapshot.duplicate(true)
