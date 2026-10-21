extends Node3D
## Denní cyklus: slunce, měsíc, obloha, ranní mlha a vnitřní osvětlení (Forward+).
## Slunce obíhá podle GameClock, barva a intenzita se mění se elevací.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
## Vnitřní lampy – rozsvítí se večer.
var interior_lights: Array[Light3D] = []
var _lamp_target := 0.0
var _lamp_level := 0.0

const SUN_MAX_ELEVATION := 62.0
const LAMP_ENERGY := 1.6


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.5, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.78, 0.86)
	sky_mat.ground_horizon_color = Color(0.55, 0.55, 0.5)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.18)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	# Globální osvětlení a stínování prostoru
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.ssr_enabled = false
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	# Volumetrická mlha (ráno hustší)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.006
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.2
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.shadow_enabled = true
	moon.light_energy = 0.0
	add_child(moon)

	update_cycle(get_node("/root/GameClock").day_fraction())


func add_interior_light(l: Light3D) -> void:
	interior_lights.append(l)
	l.light_energy = 0.0


func _process(delta: float) -> void:
	var clock := get_node("/root/GameClock")
	update_cycle(clock.day_fraction())
	_lamp_level = move_toward(_lamp_level, _lamp_target, delta * 0.8)
	for l in interior_lights:
		l.light_energy = _lamp_level * LAMP_ENERGY
		l.visible = _lamp_level > 0.01


## t: 0 = půlnoc, 0.25 = 6:00, 0.5 = poledne, 0.75 = 18:00.
func update_cycle(t: float) -> void:
	var angle := (t - 0.25) * TAU
	var s := sin(angle)  # >0 ve dne
	var elevation := s * SUN_MAX_ELEVATION
	var azimuth := lerpf(-110.0, 110.0, clampf((t - 0.2) / 0.6, 0.0, 1.0))
	sun.rotation_degrees = Vector3(-maxf(elevation, -10.0), azimuth, 0.0)
	var day_k := smoothstep(-0.05, 0.3, s)
	var warm := 1.0 - smoothstep(0.0, 0.45, s)
	sun.light_color = Color(1.0, 0.97, 0.92).lerp(Color(1.0, 0.55, 0.28), warm)
	sun.light_energy = 1.7 * smoothstep(-0.02, 0.18, s)
	sun.visible = s > -0.05

	var night_k := 1.0 - smoothstep(-0.2, 0.05, s)
	moon.rotation_degrees = Vector3(-40.0, azimuth + 180.0, 0.0)
	moon.light_energy = 0.12 * night_k
	moon.visible = night_k > 0.01

	sky_mat.sky_energy_multiplier = lerpf(0.04, 1.0, day_k)
	sky_mat.sky_top_color = Color(0.03, 0.04, 0.1).lerp(Color(0.3, 0.5, 0.85), day_k)
	sky_mat.sky_horizon_color = Color(0.08, 0.08, 0.15).lerp(
		Color(0.95, 0.6, 0.4).lerp(Color(0.72, 0.8, 0.9), 1.0 - warm), day_k)
	env.ambient_light_energy = lerpf(0.25, 1.0, day_k)

	# Ranní opar kolem svítání (5–9 h) a lehký večerní.
	var hours := t * 24.0
	var mist := exp(-pow((hours - 6.5) / 1.6, 2.0)) + 0.35 * exp(-pow((hours - 20.0) / 1.5, 2.0))
	env.volumetric_fog_density = 0.004 + 0.03 * mist
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95).lerp(Color(1.0, 0.8, 0.65), warm * day_k)

	# Lampy svítí, když je venku šero.
	_lamp_target = 1.0 if s < 0.12 else 0.0
