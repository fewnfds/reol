extends "res://tests/agency_food_smoke.gd"
func learning_changes_method() -> void:
 var w: RefCounted = peaceful()
 move_actor(w,4,Vector2(123.5,120.5)); move_actor(w,3,Vector2(124.5,120.5));move_actor(w,2,Vector2(180.5,180.5))
 var chest: int = w.facilities.create_completed(w,"wood_chest",w.Terrain.index(Vector2i(127,122)))
 w.objects.add(chest,"breath_manual",1)
 var tree: int = w.nature.create(w,"old_tree",w.Terrain.index(Vector2i(129,122)))
 w.objects.records[tree].stage = w.nature.Stage.MATURE; w.objects.records[tree].growth_ms = int(w.nature.definitions[w.objects.records[tree].definition].mature_ms)
 w.objects.records[tree].qi = 3000
 w.nature._sync(w,tree);w.flush_topology()
 w.pages[0].hunger[3]=10000;w.pages[0].energy[3]=10000
 resident(w,4,[3,tree])
 var goal: int = w.livelihood.add_goal(w,4,"development",{"method":"wood_breath"})
 w.decisions.prepare(w,0)
 check(w.actions.get(4,{}).get("kind")=="learn" and w.actions[4].target==3,"Self-directed learner did not try the only known contact")
 advance(w,1600)
 check(w.knowledge.records[4].experiences.any(func(e:Dictionary):return e.reason=="teacher_does_not_know"),"Failed teaching had no actual experience")
 w.knowledge.seed(w,4,w.operation_target(chest),w.elapsed_ms)
 w.decisions.wake(w,4,w.elapsed_ms,"knowledge_delivered")
 advance(w,25000)
 check(w.Growth.mastered(w.objects.records[4],"wood_breath") and w.objects.amount(chest,"breath_manual")==0 and w.objects.amount(4,"breath_manual")==1,"Rejected learner did not acquire a book, study and actually practice")
 check(w.livelihood.records[4].goals[goal].state=="completed" and w.objects.records[4].qi>0 and w.objects.records[tree].qi<3000,"Personal goal completed without actual practice consequences")
 check(Persistence.candidate(Persistence.capture(w),0)!=null,"Learning plan/negative evaluation/history failed restoration")
 var attempts: int = 0
 for result: Dictionary in w.activity_results.view(4):
  if result.operation=="learn" and result.target==3: attempts+=1
 check(attempts==1,"Learner harassed a known unqualified teacher instead of changing method")

func _run() -> void:
 learning_changes_method()
 print("AGENCY_LEARNING_SMOKE errors=",errors)
 quit(0 if errors==0 else 1)
