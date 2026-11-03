extends SceneTree
func _init() -> void: call_deferred("run")
func run() -> void:
 root.mode = Window.MODE_WINDOWED
 root.size = Vector2i(1280, 720)
 var gm := root.get_node("GameManager")
 gm.start_night(1)
 gm.minutes_per_second = 0
 var station = load("res://station_builder.tscn").instantiate()
 root.add_child(station)
 current_scene = station
 var player = get_first_node_in_group("player")
 player.set_physics_process(false)
 player.position = Vector3(0, .35, -9)
 player.rotation.y = PI
 var director = station.get_node("PassengerService")
 director.round_number = 1
 director._spawn_wave()
 director.round_number = 2
 director._spawn_wave()
 gm.sign_in()
 var camera := Camera3D.new()
 station.add_child(camera)
 camera.current = true
 camera.look_at_from_position(Vector3(5, 2.2, -7), Vector3(-2, 1.4, -13))
 for warmup in range(5): await process_frame
 root.mode = Window.MODE_WINDOWED
 root.size = Vector2i(1280, 720)
 root.content_scale_size = Vector2i(1280,720)
 camera.make_current()
 var times: Array[float] = []
 var previous := Time.get_ticks_usec()
 for frame in range(240):
  await process_frame
  var now := Time.get_ticks_usec()
  if frame >= 60: times.append((now-previous)/1000.0)
  previous = now
 RenderingServer.force_draw(false)
 root.get_texture().get_image().save_png("res://builds/passenger-redesign/station-crowd.png")
 times.sort()
 var data := {"renderer": RenderingServer.get_current_rendering_method(), "viewport": [root.get_texture().get_width(),root.get_texture().get_height()], "passengers": director.actors.size(), "frames": times.size(), "median_frame_ms": times[times.size()/2], "p95_frame_ms": times[int(times.size()*.95)], "scope": "Short local single-instance rendered sample on Apple M1 Pro; not an internet co-op or full-shift performance test."}
 var file := FileAccess.open("res://builds/passenger-redesign/render-sample.json", FileAccess.WRITE)
 file.store_string(JSON.stringify(data, "  "))
 print("RENDER SAMPLE: ", data)
 for audio in station.find_children("*", "AudioStreamPlayer3D", true, false): audio.stop()
 station.queue_free()
 for frame in range(8): await process_frame
 quit()
