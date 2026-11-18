extends "res://tests/agency_food_smoke.gd"
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
func public_repurpose_and_revocation() -> void:
 var w: RefCounted = peaceful()
 var org: int = w.institutions.create("青禾宗")
 check(w.institutions.admit(w,org,4,Array(w.institutions.PURPOSES)),"Membership fixture refused")
 move_actor(w,4,Vector2(123.5,120.5))
 var chest: int = w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(123,122)))
 var stove: int = w.facilities.create_completed(w,"cook_stove",w.Terrain.index(Vector2i(127,122)))
 w.objects.records[chest].organization=org;w.objects.records[stove].organization=org
 w.objects.add(chest,"grain",2,Stock.right(0,org));w.objects.add(chest,"water",1,Stock.right(0,org));w.objects.add(chest,"meal",1,Stock.right(0,org));w.flush_topology()
 check(w.begin_transfer(4,{"kind":"take","target":chest,"item":"meal","amount":1,"purpose":"supply"})=="accepted","Entrusted meal fixture refused")
 advance(w,1200)
 w.pages[0].hunger[3]=1000
 check(w.execute_operation(4,{"kind":"eat","target":4})=="no_food","Physical custody advertised someone else's entrusted meal as personal food")
 check(w.begin_transfer(4,{"kind":"put","target":chest,"item":"meal","amount":1})=="accepted","Unused meal could not return")
 advance(w,w.elapsed_ms+900)
 check(w.begin_transfer(4,{"kind":"take","target":chest,"item":"grain","amount":2,"purpose":"supply"})=="accepted","Wrong-purpose initial custody refused")
 advance(w,w.elapsed_ms+900)
 resident(w,4,[chest,stove])
 # The existing grain is supply stock; it may not be relabelled in a plan.
 var goal: int = w.livelihood.add_goal(w,4,"operation",{"operation":"cook","target":stove})
 w.decisions.prepare(w,w.elapsed_ms)
 advance(w,w.elapsed_ms+18000)
 check(w.livelihood.records[4].goals[goal].state=="completed" and w.facilities.completed.get("cook",0)==1,"Public supply stock did not actually return/reissue/produce under its own purpose")
 check(w.objects.amount(chest,"grain")==0 and w.objects.amount(stove,"meal")>=1,"Public method lost material or stole another purpose")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Public method failed physical-custody restoration")
 # Withdrawal after completion, then revoke use: returns must remain possible.
 w.command({"kind":"interrupt","actor":4})
 w.objects.add(chest,"water",1,Stock.right(0,org))
 check(w.begin_transfer(4,{"kind":"take","target":chest,"item":"water","amount":1,"purpose":"supply"})=="accepted","Revocation fixture refused")
 advance(w,w.elapsed_ms+2000)
 check(w.institutions.admit(w,org,4,[]),"Permission revocation fixture failed")
 resident(w,4,[chest])
 w.pages[0].hunger[3]=10000;w.pages[0].energy[3]=10000
 w.decisions.prepare(w,w.elapsed_ms)
 advance(w,w.elapsed_ms+5000)
 check(w.institutions.returns(w,4).is_empty() and w.objects.amount(chest,"water")>=1,"Revoked person could not autonomously return physical entrusted stock")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Returned revoked custody broke restoration")

func busy_method_keeps_issued_material() -> void:
 var w: RefCounted=peaceful()
 var org: int=w.institutions.create("青禾宗")
 for actor: int in [3,4]: w.institutions.admit(w,org,actor,Array(w.institutions.PURPOSES));move_actor(w,actor,Vector2(127.5,123.5))
 var chest: int=w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(123,122)))
 var stove: int=w.facilities.create_completed(w,"cook_stove",w.Terrain.index(Vector2i(127,122)))
 w.objects.records[chest].organization=org;w.objects.records[stove].organization=org
 w.objects.add(chest,"grain",4,Stock.right(0,org));w.objects.add(chest,"water",2,Stock.right(0,org));w.flush_topology()
 for actor: int in [3,4]:
  for item: String in ["grain","water"]:
   var count: int=2 if item=="grain" else 1
   check(w.institutions.move_goods(w,actor,chest,item,count,"take",{"purpose":"cook"},0).status=="completed","Busy batch legitimate issue failed")
 for item: String in ["grain","water"]:
  check(w.institutions.move_goods(w,3,stove,item,2 if item=="grain" else 1,"put",{},0).status=="completed","Competing cook did not stock table")
 move_actor(w,4,Vector2(125.5,125.5))
 check(w.begin_interaction(3,{"kind":"cook","target":stove})=="accepted","Competing cook did not occupy the real station")
 w.settle_action(3,0)
 resident(w,4,[chest,stove])
 w.pages[0].hunger[3]=10000;w.pages[0].energy[3]=10000
 var goal: int=w.livelihood.add_goal(w,4,"operation",{"operation":"cook","target":stove})
 w.decisions.prepare(w,0)
 advance(w,1100)
 check(w.objects.amount(4,"grain")+w.objects.amount(stove,"grain")==4 and w.objects.amount(chest,"grain")==0,"Brief target contention returned or lost material instead of retaining it in bag/table: "+str({"bag":w.objects.inventory_summary(4),"table":w.objects.inventory_summary(stove),"store":w.objects.inventory_summary(chest),"action":w.actions.get(4,{}),"intent":w.livelihood.records[4].intention}))
 check(w.livelihood.records[4].goals[goal].state=="active" and Persistence.candidate(Persistence.capture(w),0)!=null,"Busy method lost its continuing purpose or recovery")

func _run() -> void:
 public_repurpose_and_revocation()
 busy_method_keeps_issued_material()
 print("AGENCY_CUSTODY_SMOKE errors=",errors)
 quit(0 if errors==0 else 1)
