extends Node3D
## Chytrý objekt – nábytek, který inzeruje akce (princip „smart objects“).
## Spravuje obsazenost (kapacita) a body použití pro jednotlivá místa.

var object_tag := ""
var display_name := ""
var capacity := 1
## Lokální body (Vector3), kam postava dojde (jeden na každé místo).
var use_offsets: Array = [Vector3(0, 0, 1.0)]
## Lokální body, kde postava během akce sedí/leží (prázdné = zůstane u use_offset).
var pose_offsets: Array = []
var users: Array = []


func is_available(sim) -> bool:
	return users.has(sim) or users.size() < capacity


func reserve(sim) -> bool:
	if users.has(sim):
		return true
	if users.size() >= capacity:
		return false
	users.append(sim)
	return true


func release(sim) -> void:
	users.erase(sim)


func _slot(sim) -> int:
	return maxi(users.find(sim), 0)


func get_use_position(sim) -> Vector3:
	var i := _slot(sim) % use_offsets.size()
	return to_global(use_offsets[i])


func get_pose_position(sim) -> Vector3:
	if pose_offsets.is_empty():
		return get_use_position(sim)
	return to_global(pose_offsets[_slot(sim) % pose_offsets.size()])
