extends "res://tests/abilities_ui_smoke.gd"
## Real 2D framebuffer, reversible warp, picking and paused viewport changes.
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
	game = Game.new()
	game._actors = 4
	game._fps = 60
	game.feedback.config_path = "user://view-ui-feedback.cfg"
	game.controls.bindings.config_path = "user://view-ui-controls.cfg"
	game.paused = true
	game.runner.control(true,1)
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
	check(game.view.viewport.disable_3d and game.view.world is Node2D,"World display is not pure 2D")
	check(Art.catalog().entries.long_bed.parts.size() == 2,"Long fixture lacks independently sorted parts")
	var parts: int = 0
	for id: int in game.object_canvas.identities:
		if id == long_bed: parts += 1
	check(parts == 2,"Multi-cell object did not expand its visual parts")
	game.ui.hide()
	for amount: float in [0.0,1.0]:
		game.feedback.view_warp = amount
		await process_frame
		await process_frame
		await capture("oblique-"+str(int(amount)))
		check(game.controls.pick(Vector2(118.5,121.6)).has(wall),"Wall art extending above its occupied cell cannot be selected")
		check(not game.controls.pick(Vector2(117.8,121.6)).has(wall),"Transparent sprite area swallowed selection")
		var overlapping: Array[int] = game.controls.pick(game._displayed(4)+Vector2(0,-22.0/Art.TILE))
		check(not overlapping.is_empty() and overlapping[0] == 4,"Equal-depth picking did not choose the last drawn body")
		for zoom: float in [0.45,1.7]:
			game.camera.zoom = Vector2.ONE*zoom
			game.view.sync()
			for screen: Vector2 in [Vector2.ZERO,Vector2(1279,0),Vector2(1279,719),Vector2(0,719),Vector2(640,360),Vector2(1010,590)]:
				var point: Vector2 = game.view.ground(screen)
				check(game.view.project(point,false).distance_to(screen)<0.02,"Warp inverse drifted at an edge")
				var source: Vector2 = game.view.viewport.canvas_transform*point
				check(Rect2(Vector2.ZERO,Vector2(game.view.viewport.size)).has_point(source),"Warp exposed outside the source viewport")
			var stable: Vector2 = game.view.ground(Vector2(940,530))
			game.camera.offset = Vector2(8,-6)/game.camera.zoom
			game.view.sync()
			check(game.view.ground(Vector2(940,530)).distance_to(stable)<0.003,"Camera shake changed skill targeting")
			var drawn_wall: Vector2 = game.view.project(Vector2(118.5,121.6)*Art.TILE)
			check(game.controls.pick(game.controls.pointer_world(drawn_wall)).has(wall),"Sprite selection missed a shaken visual")
			game.camera.offset = Vector2.ZERO
		game.camera.zoom = Vector2.ONE*1.7
		game.view.sync()
		var foot: Vector2 = game._displayed(1)*Art.TILE
		var mouse_at: Vector2 = game.view.project(foot+Vector2(60,30),false)
		Input.warp_mouse(mouse_at)
		check(await until(func():return root.get_mouse_position().distance_to(mouse_at)<1.1,500),"Native cursor did not arrive at target")
		game.controls._update_aim(root.get_mouse_position())
		check(game.controls._aim.dot(Vector2(60,30).normalized())>0.999,"Native pointer aim diverged under the warp: wanted=%s actual=%s aim=%s k=%s canvas=%s" % [mouse_at,root.get_mouse_position(),game.controls._aim,game.view.strength,game.view.viewport.canvas_transform])
		check(game.fog.mask.size.x == ceili(game.view.viewport.size.x*0.5),"Fog mask missed the expanded viewport")
	# Check actual composite pixels at odd/even window sizes, not only CPU math.
	for window_size: Vector2i in [Vector2i(1281,721),Vector2i(1366,768)]:
		root.size = window_size
		for amount: float in [0.0,1.0]:
			game.feedback.view_warp = amount
			game.sync_view()
			await process_frame
			await RenderingServer.frame_post_draw
			var displayed: Image = root.get_texture().get_image()
			var source: Image = game.view.viewport.get_texture().get_image()
			var output_size: Vector2 = game.view._size
			check((game.view.viewport.size.x-int(output_size.x))%2 == 0 and (game.view.viewport.size.y-int(output_size.y))%2 == 0,"Centred source has mismatched pixel parity")
			for pixel: Vector2i in [Vector2i(210,180),Vector2i(470,320),Vector2i(810,380),Vector2i(950,610)]:
				var logical: Vector2 = root.get_stretch_transform().affine_inverse()*(Vector2(pixel)+Vector2.ONE*0.5)
				var q: Vector2 = logical/(output_size*0.5)-Vector2.ONE
				var src: Vector2 = game.view.unwarp(q,game.view.strength)*output_size*0.5+Vector2(game.view.viewport.size)*0.5
				var actual: Color = displayed.get_pixelv(pixel)
				var expected: Color = source.get_pixelv(Vector2i(src.floor()))
				check(absf(actual.r-expected.r)+absf(actual.g-expected.g)+absf(actual.b-expected.b)<0.015,"Framebuffer disagrees: window=%s root=%s source=%s output=%s pixel=%s src=%s got=%s want=%s transform=%s" % [window_size,displayed.get_size(),source.get_size(),output_size,pixel,src,actual,expected,root.get_stretch_transform()])
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F7
	toggle.physical_keycode = KEY_F7
	toggle.pressed = true
	Input.parse_input_event(toggle)
	check(is_equal_approx(game.view.strength, game.feedback.view_warp*game.ViewRig.MAX_STRENGTH),"F7 used a stale inverse until the next process")
	var before: int = game.frame.world_ms
	var size_before: Vector2i = root.size
	root.size = Vector2i(960,540)
	await process_frame
	await process_frame
	check(game.view._output.size == root.get_visible_rect().size,"Resize left stale output dimensions")
	game.view.pan_pixels(Vector2(120,60))
	await process_frame
	check(game.frame.world_ms == before,"Paused view changes advanced the simulation")
	game.ui.show()
	game.controls.action("pause_menu",{})
	game.controls.action("settings",{})
	await process_frame
	check(game.ui._modal_body.find_child("feedback_view_warp",true,false) != null,"Warp setting missing from native settings")
	await capture("settings-resized")
	root.size = size_before
	game.queue_free()
	await process_frame
	await process_frame
	for name_key: String in [path,path+".bak",path+".tmp","user://view-ui-feedback.cfg","user://view-ui-controls.cfg"]:
		if FileAccess.file_exists(name_key):DirAccess.remove_absolute(name_key)
	print("VIEW_UI_SMOKE errors=",errors)
	quit(0 if errors == 0 else 1)
