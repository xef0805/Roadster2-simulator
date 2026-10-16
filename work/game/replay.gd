extends Node

const Car = preload("res://car.gd")
const SAMPLE_STEP := 1.0/30.0
const MAX_SAMPLES := 3600
const PRE_ROLL_SAMPLES := 360
const UI_IDLE_SECONDS := 3.0
var lab: Node3D
var active := false
var playing := true
var time := 0.0
var duration := 0.0
var camera_speed := 32.0
var idle_time := 0.0
var ui_hidden := false
var manual_camera := false
var camera_target := Vector3.ZERO
var clock := 0.0
var sample_wait := 0.0
var previous_contacts := 0
var pre_roll: Array = []
var recording: Array = []
var last_clip: Array = []
var landing_tail := 0.0
var flight_seen := false
var ghost: RigidBody3D
var saved: Dictionary = {}
var panel: PanelContainer
var caption: Label
var timeline: HSlider
var status: Label

func setup(owner_lab: Node3D) -> void:
	lab = owner_lab
	if not lab.testing: _make_ui()

func _make_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	status = Label.new()
	status.text = "TAB 回放最近动作 · 包含助跑与爬坡"
	status.position = Vector2(39,90)
	status.add_theme_font_size_override("font_size",14)
	root.add_child(status)
	panel = PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = 125
	panel.offset_bottom = 253
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015,0.035,0.055,0.88)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel",style)
	root.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	caption = Label.new()
	rows.add_child(caption)
	var actions := HBoxContainer.new()
	rows.add_child(actions)
	for entry in [["播放 / 暂停 (空格)",0],["后退一秒 (←)",1],["前进一秒 (→)",2],["返回驾驶 (Tab)",3]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(_button.bind(entry[1]))
		actions.add_child(button)
	timeline = HSlider.new()
	timeline.step = 0.01
	timeline.value_changed.connect(seek)
	rows.add_child(timeline)
	var help := Label.new()
	help.text = "右键自由转向 · W/A/S/D 移动 · Q/E 降/升 · Shift 加速 · 滚轮调速度"
	help.add_theme_font_size_override("font_size",13)
	rows.add_child(help)
	panel.hide()

func _button(choice: int) -> void:
	wake_interface()
	if choice==0: playing = not playing
	elif choice==1: seek(time-1.0)
	elif choice==2: seek(time+1.0)
	else: stop()

func snapshot() -> Dictionary:
	var car = lab.car
	return {"t":clock,"pose":car.global_transform,"velocity":car.linear_velocity,"wheels":car.wheel_lengths.duplicate(),"contacts":car.wheel_contacts,"air_time":car.air_time,"controls":car.controls.duplicate(),"force":car.current_force,"torque":car.current_torque,"roll":car.roll_jet_forces.duplicate(),"lift":car.lift_amount,"thrust":car.vertical_thrust,"g":car.g_force}

func _physics_process(delta: float) -> void:
	if lab==null or active or get_tree().paused: return
	if lab.car.reset_pending:
		recording.clear()
		pre_roll.clear()
		previous_contacts = 0
		landing_tail = 0.0
		flight_seen = false
		return
	clock += delta
	sample_wait += delta
	if sample_wait<SAMPLE_STEP-0.00001: return
	sample_wait -= SAMPLE_STEP
	var frame := snapshot()
	var contacts: int = frame.contacts
	var climbing: bool = contacts>0 and lab.car.road_normal.y<0.98
	if recording.is_empty() and (climbing or (previous_contacts>0 and contacts==0)):
		recording = pre_roll.duplicate(true)
		landing_tail = 0.0
		flight_seen = false
	if not recording.is_empty():
		recording.append(frame)
		flight_seen = flight_seen or (contacts==0 and frame.air_time>0.20 and frame.pose.origin.y>1.5)
		landing_tail = landing_tail+SAMPLE_STEP if flight_seen and contacts>=3 else 0.0
		if landing_tail>=0.8 or recording.size()>=MAX_SAMPLES:
			if flight_seen:
				last_clip = recording.duplicate(true)
				if status!=null: status.text = "TAB 回放最近动作 · 已保存 %.1f 秒" % (last_clip.back().t-last_clip.front().t)
			recording.clear()
			landing_tail = 0.0
			flight_seen = false
		elif not flight_seen and contacts>=3 and not climbing and lab.car.linear_velocity.length()<0.5:
			recording.clear()
	pre_roll.append(frame)
	var buffer_limit := 30 if contacts>=3 and not climbing and lab.car.linear_velocity.length()<0.5 else PRE_ROLL_SAMPLES
	while pre_roll.size()>buffer_limit: pre_roll.pop_front()
	previous_contacts = contacts

func start() -> bool:
	if active or last_clip.size()<2:
		if status!=null: status.text = "还没有完成的起飞录像 · 先起飞并落地，再按 Tab"
		return false
	saved = {"velocity":lab.car.linear_velocity,"angular":lab.car.angular_velocity,"camera":lab.camera.global_transform,"fov":lab.camera.fov,"freeze":lab.car.freeze}
	lab.car.freeze = true
	lab.car.hide()
	lab.car.set_process(false)
	if lab.car.visual_enabled:
		for player in [lab.car.motor_audio,lab.car.road_audio,lab.car.skid_audio,lab.car.jet_audio,lab.car.impact_audio]: player.stream_paused = true
	ghost = Car.new()
	ghost.visual_enabled = not lab.testing
	ghost.audio_muted = true
	ghost.freeze = true
	ghost.collision_layer = 0
	ghost.collision_mask = 0
	lab.add_child(ghost)
	if lab.hud!=null: lab.hud.car = ghost
	active = true
	wake_interface()
	playing = true
	time = 0.0
	duration = last_clip.back().t-last_clip.front().t
	if panel!=null:
		panel.show()
		timeline.max_value = duration
		lab.find_child("DrivingHints",true,false).hide()
	lab.camera.fov = 67
	var target: Vector3 = last_clip.front().pose.origin
	manual_camera = false
	camera_target = target
	lab.camera.position = target+Vector3(8,4,9)
	lab.camera.look_at(target)
	apply_frame()
	return true

func stop() -> void:
	if not active: return
	active = false
	set_interface_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if lab.hud!=null: lab.hud.car = lab.car
	ghost.queue_free()
	ghost = null
	lab.car.show()
	lab.car.set_process(true)
	lab.car.freeze = saved.freeze
	lab.car.linear_velocity = saved.velocity
	lab.car.angular_velocity = saved.angular
	lab.camera.global_transform = saved.camera
	lab.camera.fov = saved.fov
	if lab.car.visual_enabled:
		for player in [lab.car.motor_audio,lab.car.road_audio,lab.car.skid_audio,lab.car.jet_audio,lab.car.impact_audio]: player.stream_paused = false
	if panel!=null:
		panel.hide()
		lab.find_child("DrivingHints",true,false).show()

func seek(value: float) -> void:
	if not active: return
	wake_interface()
	time = clampf(value,0,duration)
	apply_frame()

func apply_frame() -> void:
	var wanted: float = last_clip.front().t+time
	var i := mini(int(time/SAMPLE_STEP),last_clip.size()-2)
	while i>0 and last_clip[i].t>wanted: i-=1
	while i<last_clip.size()-2 and last_clip[i+1].t<wanted: i+=1
	var a: Dictionary = last_clip[i]
	var b: Dictionary = last_clip[i+1]
	var weight := clampf((wanted-float(a.t))/maxf(float(b.t)-float(a.t),0.0001),0,1)
	ghost.global_transform = a.pose.interpolate_with(b.pose,weight)
	ghost.linear_velocity = a.velocity.lerp(b.velocity,weight)
	ghost.controls = a.controls.duplicate()
	ghost.wheel_contacts = a.contacts
	ghost.current_force = a.force
	ghost.current_torque = a.torque
	ghost.roll_jet_forces.assign(a.roll)
	ghost.wheel_lengths.assign(a.wheels)
	ghost.lift_amount = a.lift
	ghost.vertical_thrust = a.thrust
	ghost.g_force = lerpf(a.g,b.g,weight)
	if not manual_camera:
		lab.camera.position += ghost.position-camera_target
		lab.camera.look_at(ghost.position+Vector3.UP*0.2)
	camera_target = ghost.position

func move_camera(delta: float, direction: Vector3, fast := false) -> void:
	if direction.length_squared()>0.0:
		manual_camera = true
		wake_interface()
	var camera: Camera3D = lab.camera
	camera.position += (camera.basis*Vector3(direction.x,0,direction.z)+Vector3.UP*direction.y).normalized()*camera_speed*(3.0 if fast else 1.0)*delta

func _process(delta: float) -> void:
	if not active: return
	idle_time += delta
	if playing:
		time = minf(duration,time+delta)
		if time>=duration: playing = false
	apply_frame()
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	move_camera(delta,direction,Input.is_physical_key_pressed(KEY_SHIFT))
	if direction.length_squared()>0.0: wake_interface()
	set_interface_visible(idle_time<UI_IDLE_SECONDS)
	if panel!=null:
		caption.text = "最近一次起飞 / 空翻    %.1f / %.1f 秒    %s" % [time,duration,"播放中" if playing else "已暂停"]
		timeline.set_value_no_signal(time)

func set_interface_visible(value: bool) -> void:
	ui_hidden = not value
	if panel!=null:
		panel.visible = active and value
		status.visible = value
		lab.hud.visible = value
		lab.find_child("GameTitle",true,false).visible = value
		lab.find_child("GameSubtitle",true,false).visible = value

func wake_interface() -> void:
	idle_time = 0.0
	set_interface_visible(true)

func rotate_camera(relative: Vector2) -> void:
	manual_camera = true
	lab.camera.rotation.y -= relative.x*0.004
	lab.camera.rotation.x = clampf(lab.camera.rotation.x+relative.y*0.004,-1.55,1.55)

func handle_input(event: InputEvent) -> void:
	if (event is InputEventMouseMotion and event.relative.length_squared()>0.01) or event is InputEventMouseButton or (event is InputEventKey and event.pressed): wake_interface()
	if event is InputEventKey and event.pressed:
		if event.physical_keycode in [KEY_TAB,KEY_ESCAPE] and not event.echo: stop()
		elif event.physical_keycode==KEY_SPACE and not event.echo: playing = not playing
		elif event.physical_keycode==KEY_LEFT: seek(time-1.0)
		elif event.physical_keycode==KEY_RIGHT: seek(time+1.0)
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP: camera_speed = minf(200,camera_speed*1.25)
		elif event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: camera_speed = maxf(4,camera_speed/1.25)
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		rotate_camera(event.relative)
