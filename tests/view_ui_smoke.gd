extends "res://tests/abilities_ui_smoke.gd"
## Native 2D drawing, stable vertical pixel edges, selection and viewport changes.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Session = preload("res://scripts/sim/kernel/session_io.gd")
const Art = preload("res://scripts/presentation/art.gd")

func capture(name_key: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs/view-ui"))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/view-ui/"+name_key+".png")

func _run() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor-1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor-1] = Vector2(119.5+actor*2, 121.4)
	w.pages[0].positions[0] = Vector2(121.5,121.64)
	w.pages[0].positions[1] = Vector2(123.5,123.5)
	w.pages[0].positions[2] = Vector2(122.5,122.5)
	w.pages[0].positions[3] = Vector2(123.5,123.5) # Equal-depth overlap is legal for bodies.
	var wall: int = 0
	for x: int in range(118,127):
		var id: int = w.facilities.create_completed(w, "wood_door" if x == 122 else "wood_wall", w.Terrain.index(Vector2i(x,122)))
		if x == 118: wall = id
	for y: int in range(119,122):
		w.facilities.create_completed(w, "wood_door" if y == 120 else "wood_wall", w.Terrain.index(Vector2i(126,y)))
	var long_bed: int = 0
	for entry: Array in [["long_bed",118,118,0],["long_bed",120,118,1],["wood_table",122,118,0],["wood_table",124,118,1],["cook_stove",118,125,0],["cook_stove",120,125,1],["cook_stove",122,125,2],["cook_stove",124,125,3]]:
		var id: int = w.facilities.create_completed(w,entry[0],w.Terrain.index(Vector2i(entry[1],entry[2])),entry[3])
		if entry[0] == "long_bed" and entry[3] == 0: long_bed = id
	w.flush_topology()
	w.perception.update(w,0,true)
	var path: String = "user://view-ui-fixture.reol"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_var({"format":Session.FORMAT,"state":Persistence.capture(w)},false)
	file.close()
	game = Game.new(); game._opening = "development"
	game._actors = 4
	game._fps = 60
	game.feedback.config_path = "user://view-ui-feedback.cfg"
	game.controls.bindings.config_path = "user://view-ui-controls.cfg"
	game.paused = true
	game.runner.control(true,1)
	# Old local display preferences must not re-enable the retired effect.
	var legacy := ConfigFile.new()
	legacy.set_value("combat","volume",0.35)
	legacy.set_value("view","warp",1.0)
	legacy.save(game.feedback.config_path)
	root.add_child(game)
	current_scene = game
	if not await until(func():return game.frame != null): check(false,"2D view not ready");quit(1);return
	var epoch: int = game.frame.epoch
	game.runner.send({"kind":"load","path":path})
	check(await until(func():return game.frame.epoch > epoch),"2D fixture failed to restore")
	game.following = false
	game.camera.position = Vector2(122.5,122.5)*Art.TILE
	game.camera.zoom = Vector2.ONE*1.7
	await RenderingServer.frame_post_draw
	root.grab_focus()
	check(await until(func():return root.has_focus() and game.controls._focused,700),"View window has no input focus")
	check(root.disable_3d and game.view.world.get_viewport() == root,"World is not using the native 2D viewport")
	check(game.view.find_children("*","SubViewport",true,false).size() == 1,"World has an intermediate render target besides the fog mask")
	check(Art.catalog().entries.long_bed.parts.size() == 2,"Long fixture lacks independently sorted parts")
	var parts: int = 0
	for id: int in game.object_canvas.identities:
		if id == long_bed: parts += 1
	check(parts == 2,"Multi-cell object did not expand its visual parts")
	check(is_equal_approx(game.feedback.volume,0.35),"Legacy display preference discarded the combat setting")
	game.ui.hide()
	await capture("native-oblique")
	check(game.controls.pick(Vector2(118.5,121.6)).has(wall),"Wall art extending above its occupied cell cannot be selected")
	check(not game.controls.pick(Vector2(117.8,121.6)).has(wall),"Transparent sprite area swallowed selection")
	var overlapping: Array[int] = game.controls.pick(game._displayed(4)+Vector2(0,-22.0/Art.TILE))
	check(not overlapping.is_empty() and overlapping[0] == 4,"Equal-depth picking did not choose the last drawn body")
	var window_before: Vector2i = root.size
	var before: int = game.frame.world_ms
	for window_size: Vector2i in [Vector2i(1280,720),Vector2i(1281,721),Vector2i(1366,768),Vector2i(960,540)]:
		root.size = window_size
		await process_frame
		await process_frame
		var size: Vector2 = root.get_visible_rect().size
		for zoom: float in [0.45,1.0,1.7]:
			game.camera.zoom = Vector2.ONE*zoom
			game.view.sync()
			for screen: Vector2 in [Vector2.ZERO,Vector2(size.x-1,0),size-Vector2.ONE,Vector2(0,size.y-1),size*0.5]:
				var point: Vector2 = game.view.ground(screen)
				check(game.view.project(point,false).distance_to(screen)<0.02,"Native screen inverse drifted at an edge")
				check(absf(game.view.project(point+Vector2(0,100),false).x-screen.x)<0.02,"Vertical world edge became slanted")
			var stable: Vector2 = game.view.ground(size*0.7)
			game.camera.offset = Vector2(8,-6)/game.camera.zoom
			game.view.sync()
			check(game.view.ground(size*0.7).distance_to(stable)<0.003,"Camera shake changed skill targeting")
			var drawn_wall: Vector2 = game.view.project(Vector2(118.5,121.6)*Art.TILE)
			check(game.controls.pick(game.controls.pointer_world(drawn_wall)).has(wall),"Sprite selection missed a shaken visual")
			game.camera.offset = Vector2.ZERO
			game.view.sync()
		game.camera.zoom = Vector2.ONE*1.7
		game.view.sync()
		var foot: Vector2 = game._displayed(1)*Art.TILE
		var mouse_at: Vector2 = game.view.project(foot+Vector2(60,30),false)
		root.warp_mouse(mouse_at)
		check(await until(func():return root.get_mouse_position().distance_to(mouse_at)<1.1,500),"Native cursor did not arrive: window=%s logical=%s actual=%s target=%s scale=%s" % [root.size,size,root.get_mouse_position(),mouse_at,root.get_stretch_transform()])
		game.controls._update_aim(root.get_mouse_position())
		check(game.controls._aim.dot(Vector2(60,30).normalized())>0.999,"Native pointer aim diverged after resizing")
		await process_frame
		check(game.fog.mask.size == Vector2i((size*0.5).ceil()),"Fog mask missed the native viewport size")
		# A hard vertical edge rendered off-centre must occupy the same columns
		# on every row. This catches the user's periodic 1px horizontal staircase.
		var anchor: Vector2 = game.view.ground(Vector2(size.x*0.8,100),true)
		var marker := Polygon2D.new()
		marker.polygon = PackedVector2Array([anchor,anchor+Vector2(3,0),anchor+Vector2(3,70),anchor+Vector2(0,70)])
		marker.color = Color.MAGENTA
		marker.z_index = 4095
		game.view.world.add_child(marker)
		await process_frame
		await RenderingServer.frame_post_draw
		var bitmap: Image = root.get_texture().get_image()
		var start: Vector2 = root.get_stretch_transform()*game.view.project(anchor)
		var end: Vector2 = root.get_stretch_transform()*game.view.project(anchor+Vector2(3,70))
		var first_column: int = -1
		for y: int in range(ceili(start.y)+3,floori(end.y)-3):
			var found: int = -1
			for x: int in range(floori(start.x)-2,ceili(end.x)+2):
				var color: Color = bitmap.get_pixel(x,y)
				if color.r>color.g*2 and color.b>color.g*2: found=x;break
			if first_column == -1: first_column=found
			check(found >= 0 and found == first_column,"Native vertical pixel edge stepped sideways")
		marker.queue_free()
		await process_frame
	game.view.pan_pixels(Vector2(120,60))
	await process_frame
	check(game.frame.world_ms == before,"Paused view changes advanced the simulation")
	game.ui.show()
	game.controls.action("pause_menu",{})
	game.controls.action("settings",{})
	await process_frame
	check(game.ui._modal_body.find_child("feedback_view_warp",true,false) == null,"Retired display setting remains in the UI")
	check(game.feedback.save_settings() == OK,"Combat preferences could not save")
	var saved := ConfigFile.new()
	check(saved.load(game.feedback.config_path) == OK and not saved.has_section("view"),"Saving preferences retained the retired display setting")
	await capture("native-settings-resized")
	root.size = window_before
	game.queue_free()
	await process_frame
	await process_frame
	for name_key: String in [path,path+".bak",path+".tmp","user://view-ui-feedback.cfg","user://view-ui-controls.cfg"]:
		if FileAccess.file_exists(name_key):DirAccess.remove_absolute(name_key)
	print("VIEW_UI_SMOKE errors=",errors)
	quit(0 if errors == 0 else 1)
