extends RefCounted
## B3 isolated coordinate adapter. World horizontal X/Z maps to LotGrid X/Y.
## Reject out-of-lot coordinates rather than silently clamping an actor.
static func world_to_cell(lot: RefCounted, world: Vector3) -> Vector2i:
	if not is_finite(world.x) or not is_finite(world.z):
		return Vector2i(-1, -1)
	var x: int = int(floor((world.x - lot.origin.x) / lot.CELL))
	var z: int = int(floor((world.z - lot.origin.y) / lot.CELL))
	if x < 0 or z < 0 or x >= lot.gw or z >= lot.gh:
		return Vector2i(-1, -1)
	return Vector2i(x, z)

static func cell_center(lot: RefCounted, cell: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(lot.origin.x + (float(cell.x) + 0.5) * lot.CELL, y, lot.origin.y + (float(cell.y) + 0.5) * lot.CELL)

