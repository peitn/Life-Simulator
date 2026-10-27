extends CanvasLayer
## PsycheFX – jak se úzkost „cítí“: zúžené vidění (vinětace), vyprané barvy, jemné pulzování
## v rytmu srdce a rozmazané okraje; ve zvuku tlumená hudba a tlukot srdce (AudioManager).
## Deprese: svět bez barev a o něco tmavší (`grey`), bez pulzu a bez vinětace – „šedý den“.
## Jen pro postavu, jejíž soukromý stav hráč vidí (offline vybraná, v MP vlastní).
## Síla podle GameSettings.distortion_strength() – lze ztlumit nebo vypnout.

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float grey : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.18, 0.16, 0.28, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float d = length(c * vec2(1.25, 1.0));
	// Mírné „dýchání“ obrazu – zoom v rytmu srdce.
	uv = vec2(0.5) + c * (1.0 - 0.006 * pulse * intensity);
	float edge = smoothstep(0.25, 0.75, d) * intensity;
	vec3 col = textureLod(screen_tex, uv, edge * 2.5).rgb;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), clamp(intensity * 0.55 + grey * 0.5, 0.0, 0.85));
	col *= 1.0 - grey * 0.12;
	float vig = smoothstep(0.85 - 0.45 * intensity - 0.06 * pulse * intensity, 0.15, d);
	col = mix(tint.rgb * g, col, mix(1.0, vig, intensity));
	COLOR = vec4(col, 1.0);
}
"""

var main: Node = null
## Aktuální úroveň 0..1 (vyhlazená) – čtou testy a AudioManager.
var level := 0.0
## Úroveň „šedi“ deprese 0..1 (vyhlazená).
var grey_level := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _beat_phase := 0.0
var _audio: Node = null
var _settings: Node = null


func _ready() -> void:
	layer = 5
	_settings = get_node_or_null("/root/GameSettings")
	_audio = get_node_or_null("/root/AudioManager")
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## Cílová úroveň z duševního stavu (0..1) – čistá funkce kvůli testům.
static func target_level(mind: Dictionary, strength: float) -> float:
	if mind.is_empty() or strength <= 0.0:
		return 0.0
	var ar: float = float(mind.get("aversive_arousal", mind.get("arousal", 0)))
	var t := clampf((ar - 40.0) / 55.0, 0.0, 1.0)
	if bool(mind.get("panic", false)):
		t = maxf(t, 0.9)
	return t * strength


## Cílová šeď deprese (0..1) – čistá funkce kvůli testům.
static func target_grey(mind: Dictionary, strength: float) -> float:
	if mind.is_empty() or strength <= 0.0:
		return 0.0
	return clampf((float(mind.get("low", 0)) - 25.0) / 55.0, 0.0, 1.0) * strength


func _visible_mind() -> Dictionary:
	if main == null:
		return {}
	var sim = main.get_selected_sim()
	if sim == null:
		return {}
	if main.net.is_networked() and String(sim.name) != main.net.my_sim:
		return {}
	var info: Dictionary = sim.hud_info()
	if not bool(info.get("private", false)):
		return {}
	return info.get("mind", {})


func _process(delta: float) -> void:
	var strength: float = _settings.distortion_strength() if _settings != null else 1.0
	var mind := _visible_mind()
	var tgt := target_level(mind, strength)
	level = move_toward(level, tgt, delta * (0.6 if tgt > level else 0.25))
	grey_level = move_toward(grey_level, target_grey(mind, strength), delta * 0.1)  # pomalu, jako nálada
	# Tep: 70 → 140 úderů/min podle úrovně.
	var bpm := lerpf(70.0, 140.0, level)
	_beat_phase = fmod(_beat_phase + delta * bpm / 60.0, 1.0)
	var pulse := exp(-_beat_phase * 9.0) + 0.6 * exp(-absf(_beat_phase - 0.28) * 14.0)
	_rect.visible = level > 0.01 or grey_level > 0.01
	_mat.set_shader_parameter("grey", grey_level)
	_mat.set_shader_parameter("intensity", level)
	_mat.set_shader_parameter("pulse", clampf(pulse, 0.0, 1.0))
	if _audio != null and _audio.has_method("set_psyche_level"):
		_audio.set_psyche_level(level, bpm)
