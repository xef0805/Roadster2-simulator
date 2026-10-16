extends SceneTree

const Lab = preload("res://main.gd")
var results := []
var passed := true
var lab: Node3D

func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func check(ok: bool, name: String, data: Dictionary = {}) -> void:
	passed = passed and ok
	results.append({"name":name,"passed":ok,"data":data})
	print("PASS " if ok else "FAIL ",name," ",JSON.stringify(data))

func run() -> void:
	lab = Lab.new()
	lab.testing = true
	root.add_child(lab)
	var car = lab.car
	var replay = lab.replay
	check(not replay.start(),"no empty replay starts")
	car.test_controls = {"lift":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,0.65,45)))
	await frames(180)
	car.test_controls = {"lift":1.0}
	await frames(180)
	car.test_controls = {"lift":1.0,"roll":1.0}
	await frames(120)
	car.test_controls = {"lift":1.0}
	await frames(1200)
	check(replay.last_clip.size()>90 and replay.last_clip.size()<replay.MAX_SAMPLES,"records actual launch through landing",{"frames":replay.last_clip.size()})
	var peak := 0.0
	var inverted := false
	for frame in replay.last_clip:
		peak = maxf(peak,frame.pose.origin.y)
		inverted = inverted or frame.pose.basis.y.y<0.0
	check(peak>5.0 and inverted,"clip contains airborne trajectory and roll",{"height":peak,"inverted":inverted})
	var before: Transform3D = car.global_transform
	car.linear_velocity = Vector3(2,0,-3)
	var velocity: Vector3 = car.linear_velocity
	check(replay.start(),"starts completed replay")
	check(not replay.ghost.audio_muted,"replay vehicle enables recorded-state car audio")
	replay.playing = false
	replay.seek(replay.duration*0.45)
	var sample_pose: Transform3D = replay.ghost.global_transform
	await frames(180)
	check(car.freeze and car.global_position.distance_to(before.origin)<0.001,"replay freezes live vehicle")
	check(replay.ghost.global_transform.origin.distance_to(sample_pose.origin)<0.001,"paused replay holds pose")
	var camera_at: Vector3 = lab.camera.position
	replay.move_camera(0.5,Vector3(1,1,-1),true)
	check(lab.camera.position.distance_to(camera_at)>10.0,"free camera moves independently")
	check(replay.ghost.global_transform.origin.distance_to(sample_pose.origin)<0.001,"free camera does not alter recorded pose")
	camera_at = lab.camera.position
	replay.move_camera(0.5,Vector3.FORWARD)
	check(absf(lab.camera.position.distance_to(camera_at)-16.0)<0.01,"default free camera travels 32 metres per second")
	camera_at = lab.camera.position
	replay.move_camera(0.25,Vector3.UP)
	check(absf(lab.camera.position.y-camera_at.y-8.0)<0.01 and absf(lab.camera.position.x-camera_at.x)<0.001,"E moves camera up in world space")
	replay.move_camera(0.25,Vector3.DOWN)
	check(lab.camera.position.distance_to(camera_at)<0.001,"Q moves camera down in world space")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_SPACE
	replay.handle_input(key)
	check(replay.playing,"Space resumes replay without applying vehicle lift")
	replay.handle_input(key)
	check(not replay.playing,"Space pauses replay")
	replay.seek(2.0)
	key.physical_keycode = KEY_LEFT
	replay.handle_input(key)
	check(absf(replay.time-1.0)<0.001,"left arrow rewinds one second")
	key.physical_keycode = KEY_RIGHT
	replay.handle_input(key)
	check(absf(replay.time-2.0)<0.001,"right arrow advances one second")
	replay._process(3.1)
	check(not replay.ui_hidden,"idle replay keeps interface visible")
	key.physical_keycode = KEY_H
	replay.handle_input(key)
	check(replay.ui_hidden,"H hides replay interface")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(0,20)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	replay.handle_input(motion)
	check(replay.ui_hidden,"mouse input preserves manual interface hiding")
	var pitch: float = lab.camera.rotation.x
	var yaw: float = lab.camera.rotation.y
	replay.rotate_camera(motion.relative)
	check(lab.camera.rotation.x<pitch and is_equal_approx(lab.camera.rotation.y,yaw),"replay vertical mouse drag reverses previous direction")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	key.physical_keycode = KEY_RIGHT
	replay.handle_input(key)
	replay.move_camera(0.1,Vector3.UP)
	replay._process(4.0)
	check(replay.ui_hidden,"seeking movement and idle preserve hidden interface")
	key.physical_keycode = KEY_H
	replay.handle_input(key)
	check(not replay.ui_hidden,"H restores replay interface")
	var free_camera: Transform3D = lab.camera.global_transform
	key.physical_keycode = KEY_R
	replay.handle_input(key)
	check(replay.time==0.0 and replay.playing and replay.ghost.position.distance_to(replay.last_clip.front().pose.origin)<0.001,"R restarts playback from first frame")
	check(lab.camera.global_transform.is_equal_approx(free_camera) and car.freeze and car.position.distance_to(before.origin)<0.001,"restart preserves free camera and frozen live car")
	replay.seek(2.0)
	replay.playing = false
	replay._button(4)
	check(replay.time==0.0 and replay.playing,"replay restart button starts from beginning")
	replay._button(5)
	check(replay.ui_hidden,"hide button hides interface")
	var landing_index := -1
	for i in range(1,replay.last_clip.size()-1):
		if replay.last_clip[i-1].contacts==0 and replay.last_clip[i].contacts>0 and replay.last_clip[i].landing>1.5:
			landing_index = i
			break
	check(landing_index>0,"recording retains landing sound strength")
	if landing_index>0:
		replay.seek(replay.last_clip[landing_index-1].t-replay.last_clip.front().t+0.001)
		replay.time = replay.last_clip[landing_index].t-replay.last_clip.front().t+0.001
		replay.apply_frame()
		check(replay.ghost.pending_impact and replay.ghost.impact_speed>1.5,"continuous playback triggers recorded landing once")
		replay.playing = false
		replay.seek(replay.time)
		check(not replay.ghost.pending_impact,"scrubbing does not trigger a landing sound")
	car.tire_slip = 4.2
	check(is_equal_approx(replay.snapshot().slip,4.2),"recording retains tire slip for replay sound")
	car.tire_slip = 0.0
	replay.seek(replay.duration+10.0)
	check(is_equal_approx(replay.time,replay.duration),"scrubbing clamps to clip end")
	replay.seek(-10.0)
	check(replay.time==0.0,"scrubbing clamps to clip start")
	replay.stop()
	check(not replay.ui_hidden,"exit restores interface visibility")
	check(not car.freeze and car.visible and car.linear_velocity.distance_to(velocity)<0.001 and car.global_position.distance_to(before.origin)<0.001,"exit restores live pose and velocity")
	lab.testing = false
	lab.orbit_held = true
	for inside in [false,true]:
		lab.cockpit = inside
		lab.orbit = Vector2.ZERO
		lab._unhandled_input(motion)
		check(is_equal_approx(lab.orbit.y,0.08) and lab.orbit.x==0.0,"driving vertical drag reversed in "+("cockpit" if inside else "chase"))
	lab.testing = true
	lab.cockpit = false
	lab.orbit_held = false
	var original_size: int = replay.last_clip.size()
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,60,45)))
	await frames(60)
	car.test_controls = {"lift":1.0}
	await frames(2)
	var force: Vector3 = car.current_force
	var fx := 0.0
	for i in range(4): fx += car.nozzle_visual_force(i).length()
	check(force.length()<0.01 and fx>1000.0,"high air Space shows exhaust without physical lift",{"force":force,"visual_force":fx})
	car.test_controls = {"lift":0.0}
	await frames(2)
	fx = 0.0
	for i in range(4): fx += car.nozzle_visual_force(i).length()
	check(fx==0.0,"high air release removes exhaust")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,0.65,45)))
	await frames(180)
	check(replay.last_clip.size()==original_size,"reset does not replace completed clip")
	lab.orbit_held = true
	lab.orbit = Vector2(PI,1.15)
	lab._update_camera(1.0)
	check(lab.camera.position.y>car.position.y+5.0,"expanded chase camera can look down from above")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(-42,0.65,22)))
	car.test_controls = {"throttle":0.0}
	await frames(180)
	var ramp_start: float = replay.clock
	car.test_controls = {"throttle":0.65}
	var departed := false
	for i in range(3600):
		await physics_frame
		if car.ramp_flip_active:
			departed = true
		if departed: car.test_controls = {"lift":1.0,"brake":0.5 if car.air_time>2.0 else 0.0}
		if not replay.last_clip.is_empty() and replay.last_clip.back().t>ramp_start and replay.recording.is_empty(): break
	var ramp_recorded: bool = not replay.last_clip.is_empty() and replay.last_clip.back().t>ramp_start
	check(ramp_recorded and replay.last_clip.front().pose.origin.y<1.0 and replay.last_clip.front().pose.origin.z> -35.0,"ramp replay begins on flat ground before climbing",{"first_pose":replay.last_clip.front().pose.origin,"frames":replay.last_clip.size()})
	check(ramp_recorded and replay.last_clip.any(func(f):return f.contacts>=3 and f.pose.basis.y.y< -0.15),"ramp replay retains contact ascent and overhang")
	var file := FileAccess.open("user://replay-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)
