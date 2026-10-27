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
var _hand_pose_picker: OptionButton
var _hand_closeup := false
var _hand_detail_button: Button
var _anatomy_picker: OptionButton
var _finger_controls: VBoxContainer
var _finger_sliders: Dictionary = {}
var _finger_joint_container: VBoxContainer
var _finger_joint_sliders: Dictionary = {}

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
    var gesture_row := HBoxContainer.new()
    gesture_row.name = "AnatomyGestureRow"
    add_child(gesture_row)
    var pose_label := Label.new()
    pose_label.text = "Ruce:"
    gesture_row.add_child(pose_label)
    _hand_pose_picker = OptionButton.new()
    _hand_pose_picker.name = "HandPosePreview"
    _hand_pose_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for entry in [["Uvolněné","relaxed"],["Otevřené","open"],
        ["Pěst","fist"],["Ukázání","point"],["Špetka","pinch"]]:
        _hand_pose_picker.add_item(String(entry[0]))
        _hand_pose_picker.set_item_metadata(_hand_pose_picker.item_count-1,entry[1])
    _hand_pose_picker.select(0)
    _hand_pose_picker.item_selected.connect(_set_hand_pose_preview)
    gesture_row.add_child(_hand_pose_picker)
    _hand_detail_button = Button.new()
    _hand_detail_button.text = "Detail ruky"
    _hand_detail_button.pressed.connect(_toggle_hand_detail)
    gesture_row.add_child(_hand_detail_button)
    var digits_toggle := Button.new()
    digits_toggle.name = "IndividualFingerControlsButton"
    digits_toggle.text = "Prsty: jednotlivě"
    digits_toggle.pressed.connect(_toggle_finger_controls)
    add_child(digits_toggle)
    _finger_controls = VBoxContainer.new()
    _finger_controls.name = "IndividualFingerControls"
    _finger_controls.visible = false
    add_child(_finger_controls)
    var names := ["Ukazováček", "Prostředníček", "Prsteníček", "Malíček", "Palec"]
    for side in ["l", "r"]:
        for digit in 5:
            var row := HBoxContainer.new()
            _finger_controls.add_child(row)
            var label := Label.new()
            label.custom_minimum_size = Vector2(145,0)
            label.text = ("L " if side == "l" else "P ") + String(names[digit])
            row.add_child(label)
            var slider := HSlider.new()
            slider.name = "Digit_" + side + "_" + str(digit)
            slider.min_value = 0.0
            slider.max_value = 1.0
            slider.step = 0.01
            slider.value = 0.0
            slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            slider.value_changed.connect(_on_individual_finger_changed.bind(side,digit))
            row.add_child(slider)
            _finger_sliders[side+"_"+str(digit)] = slider
    var joint_button := Button.new()
    joint_button.name = "FingerJointDetailsButton"
    joint_button.text = "Klouby prstů: základní / střední"
    joint_button.tooltip_text = "Samostatné vizuální ohyby dvou oblastí každého prstu. Není to fyzikální kostra."
    joint_button.pressed.connect(_toggle_finger_joint_controls)
    _finger_controls.add_child(joint_button)
    _finger_joint_container = VBoxContainer.new()
    _finger_joint_container.name = "IndividualFingerJointControls"
    _finger_joint_container.visible = false
    _finger_controls.add_child(_finger_joint_container)
    var skeletal_button := Button.new()
    skeletal_button.name = "ActualFingerSkeletonButton"
    skeletal_button.text = "Kostra článků prstů: vypnuto"
    skeletal_button.tooltip_text = "Skutečná samostatně otáčená 28kostní 3D podkostra, pouze v náhledu."
    skeletal_button.pressed.connect(_toggle_real_finger_skeleton)
    _finger_controls.add_child(skeletal_button)
    for side in ["l","r"]:
        for digit in 5:
            for joint in ["proximal","distal"]:
                var row := HBoxContainer.new()
                _finger_joint_container.add_child(row)
                var label := Label.new()
                label.custom_minimum_size = Vector2(160,0)
                label.text = (("L " if side=="l" else "P ") +
                    String(names[digit]) + (": základ" if joint=="proximal" else ": střed"))
                row.add_child(label)
                var slider := HSlider.new()
                slider.name = "Joint_"+side+"_"+str(digit)+"_"+joint
                slider.min_value = 0.0
                slider.max_value = 1.0
                slider.step = 0.01
                slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
                slider.value_changed.connect(_on_finger_joint_changed.bind(side,digit,joint))
                row.add_child(slider)
                _finger_joint_sliders[side+"_"+str(digit)+"_"+joint] = slider
    var anatomy_row := HBoxContainer.new()
    anatomy_row.name = "AnatomyLayerRow"
    add_child(anatomy_row)
    var anatomy_label := Label.new()
    anatomy_label.text = "Anatomie:"
    anatomy_row.add_child(anatomy_label)
    _anatomy_picker = OptionButton.new()
    _anatomy_picker.name = "AnatomyViewPicker"
    _anatomy_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for choice in [["Běžná postava","off"],["Kostra","bones"],
        ["Svaly","muscles"],["Chrupavky","cartilage"],["Tuk","fat"],
        ["Všechny vrstvy","all"]]:
        _anatomy_picker.add_item(String(choice[0]))
        _anatomy_picker.set_item_metadata(_anatomy_picker.item_count-1,choice[1])
    _anatomy_picker.select(0)
    _anatomy_picker.disabled = not visual.anatomy_available()
    _anatomy_picker.item_selected.connect(_on_anatomy_view_picked)
    anatomy_row.add_child(_anatomy_picker)
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
    if _hand_closeup:
        camera.size = .33
        camera.position = Vector3(.31, .83, 2.0)
        camera.look_at(Vector3(.31, .83, 0))
    else:
        camera.size = maxf(2.5, _height * 1.4)
        camera.position = Vector3(0, _height * 0.52, 4)
        camera.look_at(Vector3(0, _height * 0.52, 0))

func _turn(delta: float) -> void:
    _angle = 0.0 if is_zero_approx(delta) else wrapf(_angle + delta, -PI, PI)
    visual.rotation.y = _angle

func public_snapshot() -> Dictionary:
    return _snapshot.duplicate(true)
## These gestures belong exclusively to the 3D preview and never modify
## CharacterData, the local draft, a save, or an ENet Apply transaction.
func _set_hand_pose_preview(index: int) -> void:
    if _hand_pose_picker == null or visual == null:
        return
    if index < 0 or index >= _hand_pose_picker.item_count:
        return
    var pose: String = str(_hand_pose_picker.get_item_metadata(index))
    if visual.set_hand_pose(pose):
        var positions := {
            "open":[0.0,0.0,0.0,0.0,0.0],
            "relaxed":[0.14,0.22,0.25,0.28,0.14],
            "fist":[1.0,1.0,1.0,1.0,0.84],
            "point":[0.0,0.98,0.98,0.98,0.48],
            "pinch":[0.68,0.30,0.25,0.28,0.75]
        }
        for side in ["l","r"]:
            for digit in 5:
                var widget: HSlider = _finger_sliders.get(side+"_"+str(digit))
                if widget != null:
                    widget.set_value_no_signal(float(positions[pose][digit]))
                for joint in ["proximal","distal"]:
                    var jc:HSlider=_finger_joint_sliders.get(side+"_"+str(digit)+"_"+joint)
                    if jc!=null:
                        jc.set_value_no_signal(0.0)


func _toggle_real_finger_skeleton() -> void:
    if visual == null:
        return
    var enabled:bool=not visual.finger_skeletal_view()
    if visual.set_finger_skeletal_view(enabled):
        var button:Button=get_node_or_null(
            "IndividualFingerControls/ActualFingerSkeletonButton")
        if button!=null:
            button.text=("Kostra článků prstů: zapnuto" if enabled
                else "Kostra článků prstů: vypnuto")


func _toggle_finger_joint_controls() -> void:
    if _finger_joint_container==null:
        return
    _finger_joint_container.visible=not _finger_joint_container.visible


func _toggle_finger_controls() -> void:
    if _finger_controls == null:
        return
    _finger_controls.visible = not _finger_controls.visible
    if _finger_controls.visible and not _hand_closeup:
        _toggle_hand_detail()


func _on_individual_finger_changed(value: float, side: String, digit: int) -> void:
    if visual == null or not is_finite(value):
        return
    if visual.set_finger_curl(side,digit,clampf(value,0.0,1.0)):
        # Legacy whole-digit gesture and paired joint morphs are exclusive.
        for joint in ["proximal","distal"]:
            var slider:HSlider=_finger_joint_sliders.get(side+"_"+str(digit)+"_"+joint)
            if slider!=null:
                slider.set_value_no_signal(0.0)


func _on_finger_joint_changed(value:float,side:String,digit:int,joint:String) -> void:
    if visual==null or not is_finite(value):
        return
    if visual.set_finger_joint_bend(side,digit,joint,clampf(value,0.0,1.0)):
        # Same digit's combined channel was zeroed. Other fingers untouched.
        var slider:HSlider=_finger_sliders.get(side+"_"+str(digit))
        if slider!=null:slider.set_value_no_signal(0.0)


## A client-local educational cutaway: changing this selector never updates
## character drafts, saves, simulation state or any multiplayer RPC.
func _on_anatomy_view_picked(index: int) -> void:
    if visual == null or _anatomy_picker == null:
        return
    if index < 0 or index >= _anatomy_picker.item_count:
        return
    var layer: String = str(_anatomy_picker.get_item_metadata(index))
    if not visual.set_anatomy_view(layer):
        _anatomy_picker.select(0)
        return
    if _model_note != null:
        _model_note.text = ("Náhled návrhu" if layer == "off" else
            "Anatomický řez — modelována jsou polohová data z Blenderu; " +
            "jednotlivé tkáně jsou pouze vizuální aproximace.")

func _toggle_hand_detail() -> void:
    _hand_closeup = not _hand_closeup
    _hand_detail_button.text = "Celá postava" if _hand_closeup else "Detail ruky"
    _frame_character()