extends Node3D

const Art = preload("res://art.gd")
const Car = preload("res://car.gd")
const Hud = preload("res://hud.gd")
const Replay = preload("res://replay.gd")
const RAMP_BASE := Vector3(-42,0,-35)
const RAMP_RADIUS := 21.0
const RAMP_END := 140.0

var car: Car
var camera: Camera3D
var testing := false
var cockpit := false
var orbit := Vector2.ZERO
var orbit_distance := 7.8
var replay: Replay
var orbit_held := false
var camera_up := Vector3.UP
var hud: Hud
var hint_label: Label
var pause_panel: Control
var elapsed := 0.0
var perf_samples: Array[float] = []
var qa_mode := ""
var qa_stage := 0
var qa_busy := false
var qa_camera_override := false
var qa_audio_test := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controls()
	_world()
	car = Car.new()
	car.visual_enabled = not testing
	add_child(car)
	car.position = Vector3(-42,0.65,22)
	camera = Camera3D.new()
	camera.cull_mask = 5
	camera.fov = 67
	camera.near = 0.07
	camera.far = 700
	add_child(camera)
	camera.position = car.position+Vector3(0,3.0,8)
	camera.look_at(car.position+Vector3.UP*0.6)
	if not testing:
		_ui()
	replay = Replay.new()
	add_child(replay)
	replay.setup(self)
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--qa-"):
			qa_mode = arg
	if qa_mode in ["--qa-perf","--qa-perf-cockpit","--qa-v014","--qa-v015"]:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,true)
		DisplayServer.window_set_size(Vector2i(1920,1080))
		DisplayServer.window_set_position(Vector2i.ZERO)
	elif qa_mode=="--qa-v014-small":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS,false)
		DisplayServer.window_set_size(Vector2i(1280,720))
	if qa_mode not in ["--qa-perf","--qa-perf-cockpit"] and not testing:
		Engine.max_fps = 120
	if not qa_mode.is_empty():
		car.test_controls = {"throttle":0.0}

func _controls() -> void:
	var bindings := {"accelerate":KEY_W,"brake":KEY_S,"left":KEY_A,"right":KEY_D,"roll_left":KEY_Q,"roll_right":KEY_E,"lift":KEY_SPACE,"drift":KEY_SHIFT,"adhesion":KEY_F,"camera":KEY_C,"reset":KEY_R,"pause":KEY_ESCAPE}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action,key)

static func ramp_transform(theta: float, offset := 0.57) -> Transform3D:
	var n := Vector3(0,cos(theta),sin(theta))
	var back := Vector3(0,-sin(theta),cos(theta))
	var p := RAMP_BASE+Vector3(0,RAMP_RADIUS*(1.0-cos(theta)),-RAMP_RADIUS*sin(theta))
	return Transform3D(Basis(Vector3.RIGHT,n,back),p+n*offset)

func _world() -> void:
	var ground_mat := Art.mat(Color("15212c"),0.25,0.48)
	Art.solid_box(self,Vector3(240,1,640),Vector3(0,-0.5,50),ground_mat)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("07101d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7991af")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("050a10")
	env.fog_density = 0.0008
	environment.environment = env
	add_child(environment)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40,-28,0)
	moon.light_color = Color("b7cee7")
	moon.light_energy = 0.75
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140
	add_child(moon)
	var road := Art.mat(Color("465564"),0.30,0.5)
	road.cull_mode = BaseMaterial3D.CULL_DISABLED
	var red := Art.mat(Color("fa3f57"),0.2,0.3,1.5)
	var steel := Art.mat(Color("323f50"),0.7,0.5)
	var stripe := Art.mat(Color("adc2cd"),0.15,0.6,0.12)
	_build_ramp(road,red,steel,stripe)
	for x in [-42.0,36.0]:
		for z in range(-120,51,9):
			Art.box(self,Vector3(0.13,0.015,4.5),Vector3(x,0.012,z),stripe)
		for side in [-1.0,1.0]:
			Art.box(self,Vector3(0.07,0.025,162),Vector3(x+side*5.1,0.03,-35),red)
	for x in range(-96,97,24):
		Art.box(self,Vector3(0.035,0.01,270),Vector3(x,0.006,-35),Art.mat(Color("253744")))
	for z in range(-160,91,24):
		Art.box(self,Vector3(216,0.01,0.035),Vector3(0,0.007,z),Art.mat(Color("253744")))
	_build_obstacles()
	for pos in [Vector3(-55,0,15),Vector3(-28,0,-25),Vector3(-56,0,-66),Vector3(20,0,20),Vector3(53,0,-30),Vector3(20,0,-85)]:
		Art.beam(self,pos,pos+Vector3.UP*11,0.16,steel)
		Art.box(self,Vector3(2.7,0.12,0.65),pos+Vector3.UP*11,Art.mat(Color("d5ebff"),0.2,0.4,1.2))
		var light := OmniLight3D.new()
		light.position = pos+Vector3.UP*9.7
		light.omni_range = 35
		light.omni_attenuation = 1.1
		light.light_energy = 4.0
		light.light_color = Color("bedbff")
		add_child(light)
	_label3d("01 / OVERHANG",Vector3(-42,1.8,33),0.024)
	_label3d("02 / FLIGHT LINE",Vector3(36,1.8,40),0.024)
	_label3d("LANDING ZONE",Vector3(36,1,-100),0.018)
	for x in [-42.0,36.0]:
		for z in [24.0,27.0,30.0]:
			Art.box(self,Vector3(8.0,0.015,0.22),Vector3(x,0.03,z),stripe)
	for i in range(11):
		var h := 3.0+float((i*7)%8)
		Art.box(self,Vector3(8, h, 7),Vector3(-100+i*20,h*0.5,-174),Art.mat(Color("111d2c")))

func _build_ramp(road: Material, red: Material, steel: Material, stripe: Material) -> void:
	var verts := PackedVector3Array()
	var segments := 140
	var normals := PackedVector3Array()
	for i in range(segments):
		var a := deg_to_rad(RAMP_END)*float(i)/segments
		var b := deg_to_rad(RAMP_END)*float(i+1)/segments
		var ta := ramp_transform(a,0.0)
		var tb := ramp_transform(b,0.0)
		var p0 := ta.origin+Vector3.LEFT*3.7
		var p1 := ta.origin+Vector3.RIGHT*3.7
		var p2 := tb.origin+Vector3.RIGHT*3.7
		var p3 := tb.origin+Vector3.LEFT*3.7
		verts.append_array(PackedVector3Array([p0,p1,p2,p0,p2,p3]))
		normals.append_array(PackedVector3Array([ta.basis.y,ta.basis.y,tb.basis.y,ta.basis.y,tb.basis.y,tb.basis.y]))
		if i%2==0:
			for x in [-3.7,3.7]:
				Art.beam(self,ta.origin+Vector3(x,0,0)+ta.basis.y*0.045,tb.origin+Vector3(x,0,0)+tb.basis.y*0.045,0.07,red)
		if i%4<2:
			Art.beam(self,ta.origin+ta.basis.y*0.02,tb.origin+tb.basis.y*0.02,0.10,stripe)
		if i%10==0:
			var support_a := ta.origin-ta.basis.y*0.25
			var support_b := ta.origin-ta.basis.y*1.7
			for x in [-3.9,3.9]:
				Art.beam(self,support_a+Vector3(x,0,0),support_b+Vector3(x,0,0),0.10,steel)
				if i>0:
					var prev := ramp_transform(a-deg_to_rad(10.0),0.0)
					Art.beam(self,prev.origin-prev.basis.y*1.7+Vector3(x,0,0),support_b+Vector3(x,0,0),0.12,steel)
			Art.beam(self,support_b+Vector3.LEFT*3.9,support_b+Vector3.RIGHT*3.9,0.12,steel)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = road
	add_child(instance)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	shape.backface_collision = true
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _build_obstacles() -> void:
	var lineup := ["Cybercab","Cybertruck","Semi","Model Y","Model 3"]
	for i in range(lineup.size()):
		var parked := StaticBody3D.new()
		parked.set_meta("obstacle",lineup[i])
		add_child(parked)
		parked.position = Vector3(36,0,-4-i*6.0)
		parked.rotation.y = PI/2.0
		var dimensions: Vector3 = Art.tesla_vehicle(parked,lineup[i])
		var c := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = dimensions
		c.shape = s
		c.position.y = dimensions.y*0.5
		parked.add_child(c)
	var landing := Art.mat(Color("30ddba"),0.1,0.5,0.7)
	for x in [-5.0,5.0]:
		Art.box(self,Vector3(0.12,0.025,35),Vector3(36+x,0.025,-77),landing)
	for z in [-59.5,-94.5]:
		Art.box(self,Vector3(10,0.025,0.12),Vector3(36,0.025,z),landing)

func _label3d(text: String, pos: Vector3, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel
	label.modulate = Color("86bac9")
	label.outline_size = 0
	label.no_depth_test = false
	label.double_sided = false
	label.position = pos
	add_child(label)

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Segoe UI"])
	var theme := Theme.new()
	theme.default_font = font
	root.theme = theme
	var title := _label(root,"ROADSTER  /  FLIGHT LAB",25,Color("e0edf3"))
	title.name = "GameTitle"
	title.position = Vector2(38,28)
	var subtitle := _label(root,"自由试驾原型 v0.1.7    /    夜间测试场",15,Color("7999ad"))
	subtitle.name = "GameSubtitle"
	subtitle.position = Vector2(39,64)
	var watermark := _label(root,"GitHub · https://github.com/xef0805\n抖音 · Felix_0805",14,Color(0.75,0.87,0.94,0.74))
	watermark.name = "CreatorWatermark"
	watermark.anchor_left = 1.0
	watermark.anchor_right = 1.0
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	watermark.offset_left = -440
	watermark.offset_right = -28
	watermark.offset_top = 28
	watermark.offset_bottom = 78
	hud = Hud.new()
	hud.car = car
	root.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.name = "DrivingHints"
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -282
	panel.offset_right = -24
	panel.offset_top = -190
	panel.offset_bottom = 190
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.055,0.085,0.16)
	style.border_color = Color(0.5,0.7,0.8,0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 11
	style.content_margin_bottom = 11
	panel.add_theme_stylebox_override("panel",style)
	root.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",5)
	panel.add_child(rows)
	_label(rows,"驾驶操作",16,Color("d8e5ec"))
	for entry in [["W / S","加速 / 制动"],["A / D","转向"],["SHIFT","手刹漂移"],["SPACE","近地弹起 / 缓冲"],["Q / E","空中横滚"],["F","吸附开关"],["C","驾驶舱视角"],["鼠标右键","拖动观察"],["R","返回起点"],["ESC","暂停 / 场景选择"]]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var key := _label(row,entry[0],14,Color("9ec8d8"))
		key.custom_minimum_size.x = 85
		_label(row,entry[1],14,Color("b2c4ce"))
	hint_label = _label(rows,"",13,Color("7e9eb0"))
	hint_label.custom_minimum_size = Vector2(226,65)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_make_pause_menu(root)

func _pause_style(color: Color, border: Color, margin := 18) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(margin)
	return style

func _pause_button(parent: Node, text: String, choice: int, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 58
	button.add_theme_font_size_override("font_size",18 if primary else 16)
	var background := Color("d6edf2") if primary else Color("13232d")
	button.add_theme_color_override("font_color",Color("0c1a21") if primary else Color("d3e1e8"))
	button.add_theme_color_override("font_hover_color",Color("0c1a21") if primary else Color.WHITE)
	button.add_theme_color_override("font_pressed_color",Color("0c1a21") if primary else Color.WHITE)
	button.add_theme_stylebox_override("normal",_pause_style(background,Color(0.47,0.68,0.75,0.22)))
	button.add_theme_stylebox_override("hover",_pause_style(background.lightened(0.10),Color("8bd0df")))
	button.add_theme_stylebox_override("pressed",_pause_style(background.darkened(0.08),Color("8bd0df")))
	button.add_theme_stylebox_override("focus",_pause_style(Color.TRANSPARENT,Color("8bd0df"),0))
	button.pressed.connect(_menu_action.bind(choice))
	parent.add_child(button)
	return button

func _make_pause_menu(root: Control) -> void:
	pause_panel = Control.new()
	pause_panel.name = "PauseOverlay"
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(pause_panel)
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.004,0.012,0.020,0.76)
	pause_panel.add_child(backdrop)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -330
	card.offset_right = 330
	card.offset_top = -275
	card.offset_bottom = 275
	card.add_theme_stylebox_override("panel",_pause_style(Color("0b1822"),Color(0.45,0.65,0.73,0.3),30))
	pause_panel.add_child(card)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation",16)
	card.add_child(menu)
	var eyebrow := HBoxContainer.new()
	menu.add_child(eyebrow)
	var tag := _label(eyebrow,"Ⅱ  PAUSED",13,Color("91d2df"))
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(eyebrow,"ROADSTER  /  FLIGHT LAB",12,Color("607f8e"))
	_label(menu,"试驾暂停",36,Color("e3eff4"))
	_label(menu,"车辆已暂停，选择场景或继续试驾。",15,Color("829daa"))
	var line := ColorRect.new()
	line.color = Color(0.4,0.6,0.7,0.18)
	line.custom_minimum_size.y = 1
	menu.add_child(line)
	var resume := _pause_button(menu,"继续驾驶                                      ESC",0,true)
	resume.name = "ResumeDriving"
	_label(menu,"切换试驾区域",13,Color("829daa"))
	var scenes := HBoxContainer.new()
	scenes.add_theme_constant_override("separation",12)
	menu.add_child(scenes)
	for entry in [["01   倒挂坡道\n弧形爬升 · 翻转落地",1],["02   飞越车队\n喷气弹起 · 越障横滚",2]]:
		var button := _pause_button(scenes,entry[0],entry[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 82
	var footer := HBoxContainer.new()
	menu.add_child(footer)
	var note := _label(footer,"ESC 返回试驾",12,Color("607f8e"))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exit := _pause_button(footer,"退出游戏",3)
	exit.custom_minimum_size.y = 42
	exit.add_theme_font_size_override("font_size",14)
	pause_panel.hide()

func _menu_action(choice: int) -> void:
	if choice==3:
		get_tree().quit()
		return
	if choice>0:
		var x := -42.0 if choice==1 else 36.0
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(x,0.65,22)))
	get_tree().paused = false
	pause_panel.hide()

func _unhandled_input(event: InputEvent) -> void:
	if testing or replay.active:
		return
	if event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		pause_panel.visible = get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		orbit_held = false
	if get_tree().paused:
		return
	if event.is_action_pressed("adhesion"):
		car.adhesion = not car.adhesion
	if event.is_action_pressed("camera"):
		cockpit = not cockpit
		car.cabin.visible = not cockpit
	if event.is_action_pressed("reset"):
		var x := -42.0 if car.position.x<0.0 else 36.0
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(x,0.65,22)))
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		orbit_held = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: orbit_distance = maxf(4.0,orbit_distance-0.8)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: orbit_distance = minf(24.0,orbit_distance+0.8)
	if event is InputEventMouseMotion and orbit_held:
		orbit.x -= event.relative.x*0.005
		orbit.y = clampf(orbit.y-event.relative.y*0.004,-1.50,1.15)

func _input(event: InputEvent) -> void:
	if testing: return
	if event is InputEventKey and event.physical_keycode==KEY_TAB and event.pressed and not event.echo:
		if replay.active: replay.stop()
		elif not get_tree().paused:
			orbit_held = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			replay.start()
		get_viewport().set_input_as_handled()
	elif replay.active:
		replay.handle_input(event)
		if event is InputEventKey: get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if get_tree().paused or testing or replay.active:
		return
	elapsed += delta
	if qa_audio_test:
		car.linear_velocity = Vector3(0,0,-20)
		car.controls.throttle = 0.6
		car.wheel_contacts = 4
	car.cockpit_audio = cockpit
	if not qa_camera_override:
		_update_camera(delta)
	if car.position.x<0:
		hint_label.text = "01 / 倒挂坡道\n保持吸附爬升，离开顶端后顺势翻转。空格仅近地缓冲。"
	else:
		hint_label.text = "02 / 飞越车队\n在车队前提前起飞。Q / E 控制横滚，绿框是落地区域。"
	if car.position.y < -15 or absf(car.position.x)>115 or car.position.z< -260 or car.position.z>360:
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(-42 if car.position.x<0 else 36,0.65,22)))
	if not qa_mode.is_empty():
		_qa(delta)

func _update_camera(delta: float) -> void:
	if not orbit_held:
		orbit = orbit.lerp(Vector2.ZERO,1.0-exp(-delta*4))
	var cb := car.global_basis.orthonormalized()
	if cockpit:
		camera.global_position = car.global_transform*Vector3(-0.36,0.70,0.27)
		camera.global_basis = cb*Basis(Vector3.UP,orbit.x)*Basis(Vector3.RIGHT,orbit.y-0.04)
		camera.fov = 78
		return
	var target_up: Vector3 = car.road_normal if car.wheel_contacts>0 else Vector3.UP
	camera_up = camera_up.slerp(target_up,1.0-exp(-delta*3.5)).normalized()
	var follow_forward := -cb.z
	if car.wheel_contacts==0:
		follow_forward = follow_forward.slide(Vector3.UP).normalized()
		if follow_forward.length()<0.1:
			follow_forward = Vector3.FORWARD
	var back := -follow_forward.rotated(camera_up,orbit.x)
	var distance := orbit_distance+minf(car.linear_velocity.length()*0.035,2.0)
	var target := car.global_position+camera_up*0.75
	var elevation := clampf(0.32+orbit.y,-1.35,1.50)
	var desired := target+back*distance*cos(elevation)+camera_up*distance*sin(elevation)
	var q := PhysicsRayQueryParameters3D.create(target,desired,1,[car.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		desired = hit.position+hit.normal*0.35
	camera.global_position = camera.global_position.lerp(desired,1.0-exp(-delta*7.5))
	q.to = camera.global_position
	var interpolated_hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not interpolated_hit.is_empty():
		camera.global_position = interpolated_hit.position+interpolated_hit.normal*0.35
	var look := target-camera.global_position
	if look.length()>0.1 and absf(look.normalized().dot(camera_up))<0.99:
		camera.look_at(target,camera_up)
	camera.fov = lerpf(camera.fov,67.0+minf(car.linear_velocity.length()*0.10,7.0),1.0-exp(-delta*3))

func _qa(delta: float) -> void:
	if qa_mode=="--qa-visual":
		if elapsed>2.0 and qa_stage==0:
			camera.position = Vector3(-13,26,35)
			camera.look_at(Vector3(-40,15,-38))
			qa_stage = 1
		elif qa_stage==1:
			_update_qa_view()
		elif qa_stage==2:
			get_tree().quit()
	elif qa_mode=="--qa-gallery" and not qa_busy:
		qa_busy = true
		_gallery()
	elif qa_mode=="--qa-roll-jets" and not qa_busy:
		qa_busy = true
		_roll_jet_gallery()
	elif qa_mode=="--qa-v012" and not qa_busy:
		qa_busy = true
		_revision_gallery()
	elif qa_mode=="--qa-v013" and not qa_busy:
		qa_busy = true
		_driving_gallery()
	elif qa_mode=="--qa-v014" and not qa_busy:
		qa_busy = true
		_hud_gallery()
	elif qa_mode=="--qa-v014-small" and not qa_busy:
		qa_busy = true
		_small_hud_view()
	elif qa_mode=="--qa-v015" and not qa_busy:
		qa_busy = true
		_final_gallery()
	elif qa_mode=="--qa-current" and not qa_busy:
		qa_busy = true
		_current_gallery()
	elif qa_mode in ["--qa-perf","--qa-perf-cockpit"]:
		if qa_mode=="--qa-perf-cockpit":
			cockpit = true
			car.cabin.hide()
		if elapsed>2.0:
			perf_samples.append(delta)
		if elapsed>14.0:
			if qa_busy: return
			qa_busy = true
			var total := 0.0
			for sample in perf_samples: total+=sample
			perf_samples.sort()
			await RenderingServer.frame_post_draw
			var rendered := get_viewport().get_texture().get_image()
			var report_name := "performance-cockpit" if cockpit else "performance"
			rendered.save_png("user://"+report_name+".png")
			var report := {"resolution":DisplayServer.window_get_size(),"render_resolution":rendered.get_size(),"texture_size":get_viewport().get_texture().get_size(),"frames":perf_samples.size(),"average_fps":perf_samples.size()/total,"p95_frame_ms":perf_samples[int(perf_samples.size()*0.95)]*1000.0,"renderer":RenderingServer.get_video_adapter_name()}
			var f := FileAccess.open("user://"+report_name+".json",FileAccess.WRITE)
			f.store_string(JSON.stringify(report,"  "))
			print("PERFORMANCE ",JSON.stringify(report))
			get_tree().quit()
		else:
			car.test_controls = {"throttle":0.5 if elapsed<4.2 else 0.0,"lift":0.48 if elapsed>4.2 else 0.0,"roll":0.5 if elapsed>5 and elapsed<7 else 0.0}

func _update_qa_view() -> void:
	camera.position = Vector3(-13,26,35)
	camera.look_at(Vector3(-40,15,-38))
	await RenderingServer.frame_post_draw
	var path := "user://overview.png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT ",ProjectSettings.globalize_path(path))
	qa_stage = 2

func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://"+filename+".png"
	get_viewport().get_texture().get_image().save_png(path)
	print("SCREENSHOT ",ProjectSettings.globalize_path(path))

func _hud_gallery() -> void:
	await get_tree().create_timer(0.8).timeout
	await _shot("v014_ground")
	cockpit = true
	car.cabin.hide()
	await get_tree().create_timer(0.4).timeout
	await _shot("v014_cockpit")
	cockpit = false
	car.cabin.show()
	qa_camera_override = true
	for angle in [90.0,130.0]:
		car.request_reset(ramp_transform(deg_to_rad(angle),0.46))
		await get_tree().create_timer(0.9).timeout
		camera.position = car.position+Vector3(9,3,7)
		camera.look_at(car.position)
		await _shot("v014_ramp_"+str(int(angle)))
	car.adhesion = false
	car.request_reset(Transform3D(Basis(Vector3.RIGHT,PI),Vector3(36,35,-52)))
	await get_tree().create_timer(0.12).timeout
	camera.position = car.position+Vector3(9,2,7)
	camera.look_at(car.position)
	await _shot("v014_inverted")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,18,-52)))
	car.test_controls = {"lift":0.65}
	await get_tree().create_timer(0.8).timeout
	camera.position = car.position+Vector3(7,3,8)
	camera.look_at(car.position)
	await _shot("v014_lift")
	for roll in [-1.0,1.0]:
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,20,-52)))
		car.test_controls = {"lift":0.45,"roll":roll}
		await get_tree().create_timer(0.4).timeout
		camera.position = car.position+Vector3(7,3,8)
		camera.look_at(car.position)
		await _shot("v014_roll_left" if roll<0 else "v014_roll_right")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,22,-52)))
	car.test_controls = {"throttle":0.0}
	await get_tree().create_timer(0.7).timeout
	camera.position = car.position+Vector3(7,3,8)
	camera.look_at(car.position)
	await _shot("v014_freefall")
	get_tree().quit()

func _small_hud_view() -> void:
	await get_tree().create_timer(1.0).timeout
	await _shot("v014_720p")
	get_tree().quit()

func _audio_sample(capture: AudioEffectCapture, inside: bool) -> Dictionary:
	cockpit = inside
	car.cabin.visible = not inside
	qa_camera_override = false
	await get_tree().create_timer(0.8).timeout
	capture.clear_buffer()
	await get_tree().create_timer(2.0).timeout
	var samples := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var energy := 0.0
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	for i in range(samples.size()):
		var sample := samples[i]
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		energy += sample.length_squared()
		bytes.encode_s16(i*4,int(clampf(sample.x,-1.0,1.0)*32767))
		bytes.encode_s16(i*4+2,int(clampf(sample.y,-1.0,1.0)*32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.data = bytes
	wav.save_to_wav("user://v015-audio-"+("cabin" if inside else "chase")+".wav")
	return {"rms":sqrt(energy/maxi(1,samples.size()*2)),"peak":peak,"frames":samples.size(),"motor_db":car.motor_audio.volume_db,"gain_db":car.audio_view_gain}

func _current_gallery() -> void:
	await get_tree().create_timer(0.8).timeout
	var report := {"window_mode":DisplayServer.window_get_mode(),"borderless":DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS),"screen_size":DisplayServer.screen_get_size(),"watermark":find_child("CreatorWatermark",true,false).text}
	await _shot("current_drive")
	qa_camera_override = true
	camera.position = car.position+Vector3(3.3,0.95,-4.4)
	camera.look_at(car.position+Vector3.UP*0.25)
	await _shot("current_model_front")
	camera.position = car.position+Vector3(-3.4,1.5,4.1)
	camera.look_at(car.position+Vector3.UP*0.25)
	await _shot("current_model_rear")
	camera.position = car.position+Vector3(-3.0,0.78,0.05)
	camera.look_at(car.position+Vector3(-0.3,0.43,0.15))
	await _shot("current_side_driver")
	var side_window := car.find_child("SideGlassLeft",true,false) as MeshInstance3D
	report.side_window_alpha = (side_window.material_override as StandardMaterial3D).albedo_color.a
	var pause_event := InputEventAction.new()
	pause_event.action = "pause"
	pause_event.pressed = true
	_unhandled_input(pause_event)
	await get_tree().create_timer(0.15).timeout
	await _shot("current_pause_menu")
	report.pause_menu_visible = pause_panel.visible and get_tree().paused
	_menu_action(0)
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,35,-70)))
	car.test_controls = {"lift":1.0}
	await get_tree().create_timer(0.5).timeout
	camera.position = car.position+Vector3(6,1.5,6)
	camera.look_at(car.position)
	await _shot("current_high_air_exhaust")
	report.high_air_thrust = car.vertical_thrust
	report.high_air_jet_count = car.jet_nodes.filter(func(j):return j.emitting).size()
	report.high_air_fog = car.dust.emitting
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,0.65,22)))
	await get_tree().create_timer(1.2).timeout
	car.test_controls = {"lift":1.0}
	await get_tree().create_timer(0.5).timeout
	camera.position = car.position+Vector3(6,2.5,6)
	camera.look_at(car.position)
	await _shot("current_ground_vapor")
	await get_tree().create_timer(1.0).timeout
	car.test_controls = {"lift":1.0,"roll":1.0}
	await get_tree().create_timer(0.8).timeout
	camera.position = car.position+Vector3(6,2,6)
	camera.look_at(car.position)
	await _shot("current_roll")
	await get_tree().create_timer(0.2).timeout
	car.test_controls = {"lift":1.0}
	await get_tree().create_timer(5.5).timeout
	var live_pose := car.global_transform
	report.replay_started = replay.start()
	if replay.active:
		replay.playing = false
		var peak_time := 0.0
		var max_y := 0.0
		for frame in replay.last_clip:
			if frame.pose.origin.y>max_y:
				max_y = frame.pose.origin.y
				peak_time = frame.t-replay.last_clip.front().t
		replay.seek(peak_time)
		camera.position = replay.ghost.position+Vector3(5,2,-6)
		camera.look_at(replay.ghost.position)
		await get_tree().create_timer(0.15).timeout
		await _shot("current_replay_front")
		replay.move_camera(0.7,Vector3(1,1,0))
		camera.look_at(replay.ghost.position)
		await _shot("current_replay_free_camera")
		await get_tree().create_timer(3.2).timeout
		await _shot("current_replay_clean")
		report.replay_idle_hides_interface = replay.ui_hidden and not replay.panel.visible and not hud.visible and not replay.status.visible
		report.idle_keeps_watermark = find_child("CreatorWatermark",true,false).is_visible_in_tree()
		var key := InputEventKey.new()
		key.pressed = true
		key.physical_keycode = KEY_SPACE
		replay.handle_input(key)
		report.space_toggles_playback = replay.playing
		replay.playing = false
		replay.seek(2.0)
		key.physical_keycode = KEY_LEFT
		replay.handle_input(key)
		report.left_seeks = is_equal_approx(replay.time,1.0)
		key.physical_keycode = KEY_RIGHT
		replay.handle_input(key)
		report.right_seeks = is_equal_approx(replay.time,2.0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		var before_pitch := camera.rotation.x
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(0,20)
		replay.handle_input(motion)
		report.mouse_pitch_corrected = camera.rotation.x>before_pitch
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		report.input_restores_interface = not replay.ui_hidden and replay.panel.visible and hud.visible
		report.clip_frames = replay.last_clip.size()
		report.clip_seconds = replay.duration
		report.live_car_drift_during_replay = car.position.distance_to(live_pose.origin)
		replay.stop()
		report.restored_position_error = car.position.distance_to(live_pose.origin)
	qa_camera_override = false
	car.test_controls = {"throttle":0.0}
	cockpit = true
	car.cabin.hide()
	await get_tree().create_timer(0.4).timeout
	await _shot("current_cockpit")
	car.mirror_view.get_texture().get_image().save_png("user://current_mirror_view.png")
	report.mirror_visible_in_cockpit = car.cockpit_mirror.visible and car.mirror_view.render_target_update_mode==SubViewport.UPDATE_ALWAYS
	report.driver_hidden_from_main_camera = camera.cull_mask & 2 == 0
	report.mirror_camera_sees_driver = car.mirror_camera.cull_mask & 2 != 0
	report.passed = report.window_mode==DisplayServer.WINDOW_MODE_FULLSCREEN and report.high_air_thrust==0.0 and report.high_air_jet_count==4 and not report.high_air_fog and report.replay_started and report.restored_position_error<0.001 and report.replay_idle_hides_interface and report.idle_keeps_watermark and report.input_restores_interface and report.space_toggles_playback and report.left_seeks and report.right_seeks and report.mouse_pitch_corrected and report.pause_menu_visible and report.side_window_alpha==1.0 and report.mirror_visible_in_cockpit and report.driver_hidden_from_main_camera and report.mirror_camera_sees_driver
	var file := FileAccess.open("user://current-visual-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("CURRENT QA ",JSON.stringify(report))
	get_tree().quit(0 if report.passed else 1)

func _final_gallery() -> void:
	await get_tree().create_timer(0.8).timeout
	await _shot("v015_ground")
	cockpit = true
	car.cabin.hide()
	car.test_controls = {"steer":0.7}
	await get_tree().create_timer(0.5).timeout
	await _shot("v015_cockpit")
	cockpit = false
	car.cabin.show()
	car.test_controls = {"throttle":0.0}
	qa_camera_override = true
	camera.position = car.position+Vector3(-3.4,1.8,-3.2)
	camera.look_at(car.position+Vector3(0,0.45,0))
	await get_tree().create_timer(0.3).timeout
	await _shot("v015_driver")
	car.test_controls = {"lift":1.0}
	await get_tree().create_timer(0.45).timeout
	camera.position = car.position+Vector3(7,2.5,7)
	camera.look_at(car.position)
	await _shot("v015_ground_vapor")
	await get_tree().create_timer(1.25).timeout
	camera.position = car.position+Vector3(8,2.8,7)
	camera.look_at(car.position)
	await _shot("v015_ballistic_peak")
	for roll in [-1.0,1.0]:
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,20,-52)))
		car.test_controls = {"lift":1.0,"roll":roll}
		await get_tree().create_timer(0.4).timeout
		camera.position = car.position+Vector3(-4,2,6)
		camera.look_at(car.position)
		await _shot("v015_roll_left" if roll<0 else "v015_roll_right")
	car.test_controls = {"throttle":0.0}
	car.request_reset(ramp_transform(deg_to_rad(130),0.46))
	await get_tree().create_timer(0.8).timeout
	camera.position = car.position+Vector3(10,3,7)
	camera.look_at(car.position)
	await _shot("v015_overhang")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,22,-70)))
	car.test_controls = {"lift":1.0}
	for i in range(600):
		await get_tree().physics_frame
		if car.vertical_thrust>car.LIFT and car.position.y<4.0: break
	camera.position = car.position+Vector3(7,2.5,7)
	camera.look_at(car.position)
	await _shot("v015_cushion")
	await get_tree().create_timer(0.3).timeout
	await _shot("v015_landing_vapor")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,0.65,22)))
	car.test_controls = {"throttle":0.0}
	await get_tree().create_timer(1.2).timeout
	car.freeze = true
	qa_audio_test = true
	car.linear_velocity = Vector3(0,0,-20)
	car.controls.throttle = 0.6
	car.wheel_contacts = 4
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 4.0
	AudioServer.add_bus_effect(0,capture)
	var chase := await _audio_sample(capture,false)
	var cabin_sample := await _audio_sample(capture,true)
	var gain := linear_to_db(cabin_sample.rms/chase.rms)
	var report := {"chase":chase,"cabin":cabin_sample,"measured_gain_db":gain,"passed":absf(gain-1.5)<0.25 and cabin_sample.peak<0.98 and chase.frames>1000}
	var file := FileAccess.open("user://audio-view-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("AUDIO VIEW ",JSON.stringify(report))
	get_tree().quit(0 if report.passed else 1)

func _gallery() -> void:
	await get_tree().create_timer(1.0).timeout
	await _shot("drive")
	cockpit = true
	car.cabin.hide()
	await get_tree().create_timer(0.6).timeout
	await _shot("cockpit")
	cockpit = false
	car.cabin.show()
	car.request_reset(ramp_transform(deg_to_rad(118),0.46))
	await get_tree().create_timer(1.5).timeout
	await _shot("overhang")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,8,-52)))
	car.test_controls = {"lift":0.43,"roll":0.7}
	await get_tree().create_timer(1.5).timeout
	await _shot("flight")
	qa_camera_override = true
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,0.65,22)))
	camera.position = Vector3(52,7,12)
	camera.look_at(Vector3(36,1.0,-16))
	await get_tree().create_timer(0.2).timeout
	await _shot("lineup")
	camera.position = Vector3(39.2,1.7,18.3)
	camera.look_at(Vector3(36,0.9,22))
	await get_tree().create_timer(0.2).timeout
	await _shot("roadster")
	qa_camera_override = true
	camera.position = Vector3(-10,34,55)
	camera.look_at(Vector3(0,10,-42))
	await get_tree().create_timer(0.1).timeout
	await _shot("overview")
	get_tree().quit()

func _roll_jet_gallery() -> void:
	qa_camera_override = true
	for direction in [-1.0,1.0]:
		car.test_controls = {"roll":direction}
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,18,-50)))
		await get_tree().create_timer(0.40).timeout
		camera.position = car.position+Vector3(3.8,1.5,6.5)
		camera.look_at(car.position+Vector3.UP*0.2)
		await _shot("roll_left" if direction<0 else "roll_right")
	get_tree().quit()

func _revision_gallery() -> void:
	await get_tree().create_timer(0.6).timeout
	await _shot("v012_drive")
	cockpit = true
	car.cabin.hide()
	await get_tree().create_timer(0.4).timeout
	await _shot("v012_cockpit")
	cockpit = false
	car.cabin.show()
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(-42,0.65,-30)))
	await get_tree().create_timer(0.9).timeout
	car.test_controls = {"throttle":0.65}
	var departed := false
	var inverted := false
	qa_camera_override = true
	for frame in range(1800):
		await get_tree().physics_frame
		camera.position = car.position+Vector3(13,3,6)
		camera.look_at(car.position)
		if car.ramp_flip_active and not departed:
			departed = true
			car.test_controls = {"throttle":0.0}
			await _shot("v012_ramp_departure")
		if departed and not inverted and car.global_basis.y.y< -0.98:
			inverted = true
			await _shot("v012_fully_inverted")
		if inverted and car.global_basis.y.y>0.96:
			await _shot("v012_flip_complete")
			break
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(36,7,14)))
	camera.position = Vector3(44,3.6,23)
	camera.look_at(Vector3(36,0.8,14))
	await get_tree().create_timer(0.2).timeout
	for frame in range(360):
		await get_tree().physics_frame
		if car.dust_cooldown>0.0:
			break
	await get_tree().create_timer(0.12).timeout
	await _shot("v012_landing_early")
	await get_tree().create_timer(0.35).timeout
	await _shot("v012_landing_peak")
	await get_tree().create_timer(0.75).timeout
	await _shot("v012_landing_spread")
	await get_tree().create_timer(1.8).timeout
	await _shot("v012_landing_clear")
	get_tree().quit()

func _driving_gallery() -> void:
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 30.0
	AudioServer.add_bus_effect(0,capture)
	await get_tree().create_timer(0.6).timeout
	await _shot("v013_controls")
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(65,0.65,35)))
	await get_tree().create_timer(0.5).timeout
	car.test_controls = {"throttle":0.85}
	await get_tree().create_timer(2.0).timeout
	var motor_pitch_low := car.motor_audio.pitch_scale
	await get_tree().create_timer(0.8).timeout
	var motor_pitch_high := car.motor_audio.pitch_scale
	var moving_db := car.motor_audio.volume_db
	car.test_controls = {"throttle":0.4,"steer":0.65,"drift":1.0}
	await get_tree().create_timer(0.8).timeout
	qa_camera_override = true
	camera.position = car.position+Vector3(6,3.1,6)
	camera.look_at(car.position+Vector3.UP*0.4)
	await _shot("v013_drift")
	var slip := car.tire_slip
	var skid_db := car.skid_audio.volume_db
	car.test_controls = {"throttle":0.2}
	await get_tree().create_timer(1.5).timeout
	camera.position = car.position+Vector3(5,3,7)
	camera.look_at(car.position)
	await _shot("v013_grip_recovered")
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(-42,0.65,22)))
	await get_tree().create_timer(0.8).timeout
	car.test_controls = {"throttle":1.0}
	for frame in range(1200):
		await get_tree().physics_frame
		camera.position = car.position+Vector3(12,3,5)
		camera.look_at(car.position)
		if car.ramp_flip_active:
			car.test_controls = {"throttle":0.0}
			await _shot("v013_ramp_departure")
			break
	await get_tree().create_timer(1.1).timeout
	camera.position = car.position+Vector3(12,3,5)
	camera.look_at(car.position)
	await _shot("v013_inversion")
	var previous := car.position
	var teleported := false
	var landed := false
	for frame in range(960):
		await get_tree().physics_frame
		teleported = teleported or previous.distance_to(car.position)>10.0
		previous = car.position
		camera.position = car.position+Vector3(9,3,7)
		camera.look_at(car.position)
		if car.wheel_contacts>=3 and car.position.y<1.5:
			landed = true
			break
	await get_tree().create_timer(0.3).timeout
	await _shot("v013_ramp_landing")
	var samples := capture.get_buffer(capture.get_frames_available())
	var bytes := PackedByteArray()
	bytes.resize(samples.size()*4)
	var peak := 0.0
	var energy := 0.0
	for i in range(samples.size()):
		var sample := samples[i]
		peak = maxf(peak,maxf(absf(sample.x),absf(sample.y)))
		energy += sample.length_squared()
		bytes.encode_s16(i*4,int(clampf(sample.x,-1.0,1.0)*32767))
		bytes.encode_s16(i*4+2,int(clampf(sample.y,-1.0,1.0)*32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.data = bytes
	wav.save_to_wav("user://v013-driving-audio.wav")
	var report := {"motor_pitch_low":motor_pitch_low,"motor_pitch_high":motor_pitch_high,"motor_db":moving_db,"drift_slip_m_s":slip,"skid_db":skid_db,"captured_frames":samples.size(),"peak":peak,"rms":sqrt(energy/maxi(1,samples.size()*2)),"full_speed_landed":landed,"flight_teleported":teleported,"landing_position":car.position}
	var file := FileAccess.open("user://driving-audio-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("DRIVING AUDIO ",JSON.stringify(report))
	get_tree().quit()
