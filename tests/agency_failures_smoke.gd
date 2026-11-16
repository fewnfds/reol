extends "res://tests/agency_food_smoke.gd"
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
func crowded_self_and_private_food() -> void:
 var w: RefCounted = peaceful()
 move_actor(w,4,Vector2(123.5,120.5))
 w.objects.add(4,"breath_manual",1)
 var stove: int = w.facilities.create_completed(w,"cook_stove",w.Terrain.index(Vector2i(125,122)))
 w.objects.add(stove,"meal",2,Stock.right(3))
 resident(w,4,[stove])
 for i: int in 55:
  var contact: Dictionary=w.operation_target(3)
  contact.id=w.objects.create("pile","identity",-1)
  contact.tile=w.Terrain.index(Vector2i(130+i%8,130+i/8))
  w.knowledge.seed(w,4,contact,0)
 w.livelihood.add_goal(w,4,"development",{"method":"wood_breath"})
 w.livelihood.record(w,4).budget.cursor=32
 w.decisions.prepare(w,0)
 check(w.actions.get(4,{}).get("kind")=="study","Crowded rotating candidates starved an immediately usable carried book")
 w.command({"kind":"interrupt","actor":4})
 check(w.execute_operation(4,{"kind":"eat","target":stove})=="no_food","Public cooker advertised another person's private output as edible")
 check(w.execute_operation(3,{"kind":"eat","target":stove})=="accepted","Owner could not consume their own output in a public cooker")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Crowded/attributed observations failed restore")

func no_food_no_pointless_preempt() -> void:
 var w: RefCounted=peaceful()
 move_actor(w,4,Vector2(123.5,120.5))
 var chest: int=w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(125,122)))
 w.objects.add(4,"wood",1)
 resident(w,4,[chest]);w.livelihood.add_goal(w,4,"delivery",{"item":"wood","amount":1,"target":chest})
 w.decisions.prepare(w,0)
 var original: Dictionary=w.gate.current(4)
 w.pages[0].hunger[3]=1000
 w.decisions.wake(w,4,0,"needs_changed");w.decisions.prepare(w,0)
 check(w.gate.current(4)==original and w.actions.get(4,{}).get("kind")=="put","Unavailable food aim pointlessly interrupted useful current work")
 check(w.livelihood.Defs.crossed_need("hunger",1801,1800),"Emergency threshold failed to produce another legal need wake")

func instant_and_obscured_inspection() -> void:
 var w: RefCounted=peaceful()
 move_actor(w,2,Vector2(123.5,120.5))
 resident(w,2,[])
 w.pages[0].health[1]=1000
 w.pools.gain(w,2,"qi",500,0)
 var goal: int=w.livelihood.add_goal(w,2,"operation",{"operation":"wood_mend","target":2})
 w.decisions.prepare(w,0)
 check(w.livelihood.records[2].goals[goal].state=="completed" and w.pages[0].health[1]>1000,"Instant operation did not settle its real personal purpose")
 check(w.decisions.wakeups.has(2),"Instant success silently stopped autonomous life")
 var other: RefCounted=peaceful()
 move_actor(other,4,Vector2(123.5,120.5))
 var wall: int=other.facilities.create_completed(other,"wood_wall",other.Terrain.index(Vector2i(128,120)))
 var chest: int=other.facilities.create_completed(other,"wood_chest",other.Terrain.index(Vector2i(130,120)))
 other.flush_topology();resident(other,4,[])
 other.objects.records[4].sight_range=7.0
 var clue: Dictionary=other.operation_target(chest);clue.erase("inventory");clue.erase("contents")
 other.knowledge.seed(other,4,clue,0)
 other.livelihood.add_goal(other,4,"delivery",{"item":"wood","amount":1})
 # A legal completed approach which still has no view must accrue a reason.
 other.adopt_motion(4,0);other.pages[0].modes[3]=other.Units.Mode.EXPLORE
 other.decisions.track_host(other,4,"inspect",chest,true)
 other.livelihood.arrived(other,4,0)
 check(other.livelihood.records[4].appraisals.has("inspect:%d"%chest),"Unobservable arrival did not prevent repeated inspect approaches")
 other.end_run(4,0,"completed")
 check(Persistence.candidate(Persistence.capture(other),0)!=null,"Inspection failure did not restore with bounded evidence")

func _run() -> void:
 crowded_self_and_private_food()
 no_food_no_pointless_preempt()
 instant_and_obscured_inspection()
 print("AGENCY_FAILURES_SMOKE errors=",errors)
 quit(0 if errors==0 else 1)


