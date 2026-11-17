extends "res://tests/agency_food_smoke.gd"

func delivery_and_budget() -> void:
 var w: RefCounted = peaceful()
 move_actor(w,4,Vector2(123.5,120.5))
 var pile: int = w.objects.create("pile","wood",w.Terrain.index(Vector2i(122,120)))
 var chest: int = w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(125,122)))
 w.objects.add(pile,"wood",3);w.objects.add(chest,"wood",7);w.flush_topology()
 resident(w,4,[pile,chest])
 var goal: int = w.livelihood.add_goal(w,4,"delivery",{"item":"wood","amount":3,"target":chest})
 decide(w, 0)
 check(w.actions.get(4,{}).get("target")==pile,"Supply goal withdrew stock from its own destination")
 var spent: int = w.livelihood.records[4].budget.work
 w.livelihood.add_goal(w,4,"development",{"method":"wood_breath"})
 check(w.livelihood.records[4].budget.work==spent,"Adding a goal reset the person's shared planning budget")
 advance(w,7000)
 check(w.objects.amount(chest,"wood")==10 and w.objects.amount(pile,"wood")==0 and w.livelihood.records[4].goals[goal].progress==3 and w.livelihood.records[4].goals[goal].state=="completed","Physical partial delivery failed to settle the matching goal")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Delivery goal/evaluation candidate was invalid")

func dispositions_and_emergency() -> void:
 var w: RefCounted = peaceful()
 move_actor(w,3,Vector2(123.5,120.5));move_actor(w,4,Vector2(124.5,120.5))
 var chest: int = w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(125,123)))
 var food: int = w.objects.create("pile","meal",w.Terrain.index(Vector2i(122,120)))
 w.objects.add(3,"wood",1);w.objects.add(4,"wood",1);w.objects.add(food,"meal",2)
 w.objects.add(3,"breath_manual",1);w.objects.add(4,"breath_manual",1);w.flush_topology()
 for actor: int in [3,4]:
  w.pages[0].hunger[actor-1]=10000;w.pages[0].energy[actor-1]=10000
  resident(w,actor,[chest,food])
  w.livelihood.add_goal(w,actor,"development",{"method":"wood_breath"})
  w.livelihood.add_goal(w,actor,"delivery",{"item":"wood","amount":1,"target":chest})
 w.livelihood.set_dispositions(w,3,{"curiosity":2.0,"dutifulness":0.1,"sociability":0.0})
 w.livelihood.set_dispositions(w,4,{"curiosity":0.1,"dutifulness":2.0,"sociability":0.0})
 decide(w, 0)
 check(w.actions.get(3,{}).get("kind")=="study" and w.actions.get(4,{}).get("kind")=="put","Relevant dispositions did not change a real same-situation action")
 var original_goal: int = w.livelihood.records[3].intention.goal
 w.pages[0].hunger[2]=500
 w.decisions.wake(w,3,0,"needs_changed");decide(w, 0)
 check(w.actions.get(3,{}).get("kind")=="eat" and w.livelihood.records[3].goals[original_goal].state=="active","Emergency hunger did not legally interrupt while preserving the longer purpose")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Emergency handoff lost the single host/restoration contract")

func malformed_personal_state() -> void:
 var w: RefCounted = peaceful()
 w.livelihood.add_goal(w,4,"development",{"method":"wood_breath"})
 var state: Dictionary = Persistence.capture(w)
 check(Persistence.candidate(state,0)!=null,"Valid personal state failed baseline restoration")
 for field: String in ["dispositions","budget","intention","goal"]:
  var bad: Dictionary = state.duplicate(true)
  var entry: Dictionary = bad.domains.livelihood.records[4]
  match field:
   "dispositions": entry.dispositions.curiosity=NAN
   "budget": entry.budget.work=-1
   "intention": entry.intention={"goal":999}
   "goal": entry.goals.values()[0].params={"method":"imaginary"}
  check(Persistence.candidate(bad,0)==null,"Malformed personal-state candidate restored: "+field)
 w.remove_actor(4)
 check(not w.livelihood.records.has(4) and Persistence.candidate(Persistence.capture(w),0)!=null,"Removed actor retained a writable personal-purpose owner")

func _run() -> void:
 delivery_and_budget()
 dispositions_and_emergency()
 malformed_personal_state()
 print("AGENCY_BOUNDARIES_SMOKE errors=",errors)
 quit(0 if errors==0 else 1)
