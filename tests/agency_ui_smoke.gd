extends "res://tests/abilities_ui_smoke.gd"
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
func capture(name_key: String) -> void:
 var directory: String = "res://logs/agency-ui/"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(directory+name_key+".png")
func find_button(node: Node, title: String) -> Button:
 if node is Button and node.text==title:return node
 for child: Node in node.get_children():
  var result: Button=find_button(child,title)
  if result!=null:return result
 return null
func _run() -> void:
 var w := World.new()
 w.initialize(4,0)
 for actor: int in w.actor_slots:
  w.release(actor);w.objects.records[actor].autonomous=false;w.objects.records[actor].side=0
  w.pages[0].positions[actor-1]=Vector2(122.5+actor,124.5)
 w.objects.add(4,"breath_manual",1)
 w.livelihood.records.erase(4)
 w.objects.records[4].autonomous=true
 w.livelihood.add_goal(w,4,"development",{"method":"wood_breath"})
 w.decisions.resume(w,4,0);w.decisions.prepare(w,0)
 w.step(16);w.perception.update(w,w.elapsed_ms,true)
 var path: String="user://agency-ui-fixture.reol"
 var file:=FileAccess.open(path,FileAccess.WRITE)
 file.store_var({"format":SessionIO.FORMAT,"state":Persistence.capture(w)},false);file.close()
 game=Game.new(); game._opening = "development";game._actors=4
 game.controls.bindings.config_path="user://agency-ui-controls.cfg"
 game.feedback.config_path="user://agency-ui-feedback.cfg"
 game.paused=true;game.runner.control(true,1)
 root.add_child(game);current_scene=game;root.grab_focus()
 check(await until(func():return game.frame!=null),"Agency UI initial frame absent")
 var epoch: int=game.frame.epoch
 game.runner.send({"kind":"load","path":path})
 check(await until(func():return game.frame.epoch>epoch),"Real personal-purpose file was not loaded")
 game.controls.action("context",{})
 game.controls._select(4,-1)
 check(await until(func():return game.ui._target.get("id",0)==4 and not game.ui._target.get("agency",{}).is_empty()),"NPC personal-purpose snapshot missing")
 var button: Button=find_button(game.ui,"人物")
 check(button!=null,"Native character toolbar button missing")
 if button!=null: await click(button)
 check(await until(func():return is_instance_valid(game.ui.character)),"Native character view failed to open")
 var panel: Control=game.ui.character
 var tabs: TabBar=panel._tabs.get_tab_bar()
 var tab_rect: Rect2=tabs.get_tab_rect(1)
 var point: Vector2=tabs.get_global_transform_with_canvas()*tab_rect.get_center()
 await mouse(MOUSE_BUTTON_LEFT,true,point);await mouse(MOUSE_BUTTON_LEFT,false,point)
 check(panel._tabs.current_tab==1 and not panel._practice.text.contains("当前打算"),"Ordinary character panel exposed private motives")
 await key(KEY_F12,true);await key(KEY_F12,false)
 var console: Node=game._debug_console
 check(console!=null and console.is_open(),"F12 agency diagnostics absent")
 if console!=null:
  console._command.text="decisions"
  await key(KEY_ENTER,true);await key(KEY_ENTER,false)
  check(console._output.text.contains("selected_agency") and console._output.text.contains("精进本领"),"Decision diagnostics omitted the selected personal purpose")
  await capture("learning-purpose")
 await key(KEY_F12,true);await key(KEY_F12,false)
 var sequence: int=game.runner.send({"kind":"save","path":path})
 check(await until(func():return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved")),"Real personal-purpose save did not finish")
 epoch=game.frame.epoch;game.runner.send({"kind":"load","path":path})
 check(await until(func():return game.frame.epoch>epoch),"Saved goal and action did not restore through the normal session")
 game.controls._select(4,-1)
 check(await until(func():return game.ui._target.get("id",0)==4),"Restored NPC could not be inspected")
 game.controls.action("pause",{})
 check(await until(func():return not game.frame.paused),"Agency play session did not resume")
 check(await until(func():return game.ui._target.get("methods",{}).get("wood_breath",{}).get("understanding",0)>=200,2500),"Visible self-directed reader did not actually learn")
 game.controls.action("pause",{})
 check(await until(func():return game.frame.paused),"Agency inspection did not pause")
 await capture("reader-restored")
 game.queue_free();await process_frame;await process_frame
 for cleanup: String in [path,path+".bak",path+".tmp","user://agency-ui-controls.cfg","user://agency-ui-feedback.cfg"]:
  if FileAccess.file_exists(cleanup):DirAccess.remove_absolute(cleanup)
 print("AGENCY_UI_SMOKE errors=",errors)
 quit(0 if errors==0 else 1)
