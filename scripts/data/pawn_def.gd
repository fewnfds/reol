class_name PawnDef
extends RefCounted
## Static pawn definition loaded from `data/pawns.json`.
## Runtime values (hunger, contribution, ...) live in PawnState.

var id: StringName = &""
var display_name: String = ""
var origin_id: StringName = &""
var rank_id: StringName = &""
var role: String = ""
var realm: int = 0
var max_qi: int = 10
var max_stamina: int = 100
var color: Color = Color.WHITE
var bio: String = ""
