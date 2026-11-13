extends SceneTree
## Narrow counterexamples for thermal tolerance and bounded personal history.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Events = preload("res://scripts/sim/kernel/person_events.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Text = preload("res://scripts/presentation/ui/event_text.gd")
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message); push_error(message)

func _initialize() -> void:
	var w := World.new()
	w.initialize(2, 0)
	var tile: int = 195 * 512 + 207
	var values := PackedInt32Array(); values.resize(7)
	w.environment.sample_raw(tile, values, 0)
	check(w.environment.mobile_units.is_empty() and values[0] == 0 and values[1] == 0 and is_equal_approx(w.environment.temperature_at(tile, values, 0), 22.0), "Normal world retained the hidden thermal fixture")
	var stress := World.new()
	stress.initialize(2, 0, true)
	stress.environment.sample_raw(tile, values, 0)
	check(stress.environment.source_cells.size() >= 96 and stress.environment.mobile_units.size() == 1 and values[1] > 50, "Explicit stress fields lost their load")
	var page: RefCounted = w.pages[0]
	page.positions[0] = Vector2(207.5,195.5)
	page.body_heat[0] = 500.0
	page.tolerance[0] = 1.25
	page.end_ms = 1000
	page.sample_environment()
	check(page.health[0] == 100 and is_equal_approx(page.tolerance[0], 0.25), "Thermal damage bypassed available tolerance")
	page.end_ms = 2000
	page.sample_environment()
	check(page.health[0] == 100 and page.tolerance[0] == 0 and is_equal_approx(page.thermal_carry[0],0.75), "Partial tolerance discarded residual damage")
	page.end_ms = 3000
	page.sample_environment()
	check(page.health[0] == 99 and is_equal_approx(page.thermal_carry[0],0.75), "Depleted tolerance granted free full hits")
	page.body_heat[0] = 22.0
	page.sample_environment()
	check(page.tolerance[0] == 1.0 and page.health[0] == 99, "Safe recovery altered HP or did not recover slowly")
	var source: int = w.environment.add_source(tile,1,120)
	page.tolerance[0] = 5.0
	page.sample_environment()
	check(page.tolerance[0] == 5.0, "Dangerous ambient temperature allowed recharging")
	w.environment.release_source(source)
	page.body_heat[0] = -10.0
	page.sample_environment()
	check(page.tolerance[0] == 4.0, "Residual exposure was cleared on leaving a source")
	page.body_heat[0] = 22.0
	page.tolerance[0] = 12.5
	page.thermal_carry[0] = 0.25
	w.elapsed_ms = 3000
	w.command({"kind":"move","actor":1,"position":Vector2(208.2,195.5)})
	check(w.person_events.view(1).back().kind == "order", "Admitted move was recorded as completion")
	var hp: int = page.health[0]
	w.combat.damage(w,2,1,10,3000)
	check(page.health[0] == hp-10 and page.tolerance[0] == 12.5, "Thermal tolerance incorrectly absorbed combat damage")
	check(not w.person_events.view(1).back().has("target"), "Damage history disclosed an attacker identity")
	var state: Dictionary = Persistence.capture(w)
	var restored: RefCounted = Persistence.candidate(state,0)
	check(restored != null and restored.pages[0].tolerance[0] == 12.5 and restored.pages[0].thermal_carry[0] == 0.25 and restored.person_events.view(1) == w.person_events.view(1), "Tolerance/history did not restore the saved world")
	state.pages[0].tolerance[0] = NAN
	check(Persistence.candidate(state,0) == null and page.tolerance[0] == 12.5, "Invalid tolerance was adopted or changed the live world")
	var history := Events.new()
	var event := {"kind":"thermal_hit","cause":"cold","at_ms":1000,"absorbed":1.0,"damage":0,"tolerance":99.0,"hp":100,"temperature":-20.0}
	history.record(1,event)
	var frozen: Array = history.view(1)
	event.at_ms = 2000; event.tolerance = 98.0
	history.record(1,event)
	check(history.view(1).size() == 1 and history.view(1)[0].count == 2 and frozen[0].count == 1, "Continuous history did not merge or mutated a published view")
	check(Text.line(history.view(1)[0]).contains("寒冷") and Text.line(history.view(1)[0]).contains("耐受"), "Personal event lacked localized consequences")
	for i: int in 300: history.record(1,{"kind":"arrived","at_ms":3000+i})
	for i: int in 2300: history.record(2+i%80,{"kind":"arrived","at_ms":4000+i})
	check(history.player.size() == Events.PLAYER_LIMIT and history.recent.size() == Events.RECENT_LIMIT and history.view(2).size() <= Events.NPC_LIMIT, "Personal histories exceeded their fixed budgets")
	var copied := Events.new()
	State.apply(copied, Events.STATE_FIELDS, State.capture(history, Events.STATE_FIELDS))
	check(copied.rebuild(10000) and copied.view(2) == history.view(2) and copied.view(1) == history.view(1), "Wrapped history ring failed restoration")
	page.health[0] = 1
	w.combat.damage(w,2,1,10,3000)
	var entries: Array = w.person_events.view(1)
	check(entries[-2].kind == "hit" and entries[-1].kind == "death" and page.tolerance[0] == 0, "Lethal hit/death order or corpse tolerance was wrong")
	page.sample_environment()
	check(page.tolerance[0] == 0 and page.health[0] == 0, "Dead body recharged tolerance")
	print("EXPERIENCE_SMOKE ",JSON.stringify({"errors":errors,"normal_temperature":22,"stress_cold":values[1]}))
	quit(0 if errors.is_empty() else 1)
