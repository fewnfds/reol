class_name PawnState
extends RefCounted
## Runtime state for one pawn. The static definition stays in PawnDef.

const MAX_NEED: float = 100.0

var pawn_def: PawnDef
var origin: OriginDef
var rank: RankDef

var qi: int = 0
var stamina: int = 0
var hunger: float = MAX_NEED
var energy: float = MAX_NEED
var mood: float = 60.0


static func create(definition: PawnDef, db: ReolContentDB) -> PawnState:
	var state := PawnState.new()
	if definition == null:
		return state
	state.pawn_def = definition
	if db != null:
		state.origin = db.get_origin(definition.origin_id)
		state.rank = db.get_rank(definition.rank_id)
	state.qi = definition.max_qi
	state.stamina = definition.max_stamina
	return state


func display_name() -> String:
	return pawn_def.display_name if pawn_def != null else "?"


func role_name() -> String:
	return pawn_def.role if pawn_def != null else ""


func rank_name() -> String:
	return rank.display_name if rank != null else "无"


func origin_name() -> String:
	return origin.display_name if origin != null else "无"


func realm_name() -> String:
	var realm: int = pawn_def.realm if pawn_def != null else 0
	return "炼气 %d 层" % (realm + 1)


func bio_text() -> String:
	return pawn_def.bio if pawn_def != null else ""


func max_qi() -> int:
	return pawn_def.max_qi if pawn_def != null else 0


func max_stamina() -> int:
	return pawn_def.max_stamina if pawn_def != null else 0


func adjust_qi(amount: int) -> void:
	qi = clampi(qi + amount, 0, max_qi())


func adjust_stamina(amount: int) -> void:
	stamina = clampi(stamina + amount, 0, max_stamina())


func adjust_hunger(amount: float) -> void:
	hunger = clampf(hunger + amount, 0.0, MAX_NEED)


func adjust_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, MAX_NEED)


func adjust_mood(amount: float) -> void:
	mood = clampf(mood + amount, 0.0, MAX_NEED)


func can_promote_to(next_rank: RankDef, recognized_contribution: int) -> bool:
	if next_rank == null or rank == null:
		return false
	if next_rank.tier <= rank.tier:
		return false
	return recognized_contribution >= next_rank.required_contribution


func promote_to(next_rank: RankDef, recognized_contribution: int) -> bool:
	# Called after the responsible institution approves. Eligibility is no approval.
	if not can_promote_to(next_rank, recognized_contribution):
		return false
	rank = next_rank
	return true
