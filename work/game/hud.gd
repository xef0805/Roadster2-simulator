extends Control

const Art = preload("res://art.gd")
var car: RigidBody3D
var attitude_car: Node3D
var attitude_view: SubViewportContainer
var digits: SystemFont
var caption: SystemFont
var shade: GradientTexture2D
var pulse := 0.0
var white := Color(0.92,0.96,0.98,0.94)
var dim := Color(0.65,0.73,0.77,0.38)
var cyan := Color(0.55,0.87,1.0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	digits = SystemFont.new()
	digits.font_names = PackedStringArray(["Bahnschrift","Consolas"])
	caption = SystemFont.new()
	caption.font_names = PackedStringArray(["Microsoft YaHei UI","Segoe UI"])
	shade = GradientTexture2D.new()
	shade.width = 4
	shade.height = 256
	shade.fill_from = Vector2.ZERO
	shade.fill_to = Vector2(0,1)
	shade.gradient = Gradient.new()
	shade.gradient.set_color(0,Color(0.002,0.006,0.01,0))
	shade.gradient.set_color(1,Color(0.002,0.006,0.01,0.60))
	_make_attitude()
	resized.connect(_layout)
	_layout()

func _make_attitude() -> void:
	attitude_view = SubViewportContainer.new()
	attitude_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attitude_view.stretch = true
	add_child(attitude_view)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(304,304)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	attitude_view.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	environment.environment = env
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 1.4
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.3
	scene.add_child(camera)
	camera.position = Vector3(7,2.8,6)
	camera.look_at(Vector3.ZERO)
	var grid := SurfaceTool.new()
	grid.begin(Mesh.PRIMITIVE_LINES)
	for plane in range(3):
		for i in range(96):
			for angle in [TAU*i/96.0,TAU*(i+1)/96.0]:
				var p := Vector3(cos(angle),0,sin(angle))*3.05
				if plane==1: p = Vector3(p.x,p.z,0)
				elif plane==2: p = Vector3(0,p.x,p.z)
				grid.set_color(Color(0.75,0.85,0.90,0.48) if plane==0 else Color(0.55,0.68,0.76,0.18))
				grid.add_vertex(p)
	var mesh := MeshInstance3D.new()
	mesh.mesh = grid.commit()
	var wire := Art.mat(Color.WHITE)
	wire.vertex_color_use_as_albedo = true
	wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = wire
	scene.add_child(mesh)
	attitude_car = Node3D.new()
	scene.add_child(attitude_car)
	var model := Node3D.new()
	attitude_car.add_child(model)
	model.scale = Vector3.ONE*1.2
	Art.car(model,Color("9da3aa"))

func _layout() -> void:
	if attitude_view==null: return
	attitude_view.position = Vector2(209,size.y-175)
	attitude_view.size = Vector2(152,152)

func _process(delta: float) -> void:
	if car==null or get_tree().paused: return
	pulse += delta*3.0
	# The grid stays in the world frame; only the miniature follows the rigid body.
	attitude_car.basis = car.global_basis.orthonormalized()
	queue_redraw()

func _text(at: Vector2, value: String, font: Font, font_size: int, color: Color) -> void:
	draw_string(font,at-Vector2(font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x*0.5,0),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _gauge(center: Vector2, title: String, value: float, maximum: float, unit: String) -> void:
	draw_circle(center,69,Color(0.005,0.012,0.02,0.34))
	var begin := deg_to_rad(140)
	var end := deg_to_rad(400)
	draw_arc(center,62,begin,end,72,dim,2.0,true)
	draw_arc(center,62,begin,lerpf(begin,end,clampf(value/maximum,0,1)),72,white,2.8,true)
	for i in range(7):
		var a := lerpf(begin,end,i/6.0)
		var direction := Vector2(cos(a),sin(a))
		draw_line(center+direction*58,center+direction*62,dim,1.0,true)
	_text(center+Vector2(0,-17),title,caption,11,Color(0.76,0.82,0.86,0.78))
	_text(center+Vector2(0,22),"%.1f" % minf(value,999.9),digits,36,white)
	_text(center+Vector2(0,41),unit,caption,11,Color(0.68,0.77,0.82,0.8))

func _draw() -> void:
	if car==null: return
	draw_texture_rect(shade,Rect2(0,size.y-210,size.x,210),false)
	var y := size.y-99
	_gauge(Vector2(106,y),"G-FORCE",car.g_force,4.0,"G")
	_text(Vector2(106,size.y-15),"%03d KM/H" % int(car.linear_velocity.length()*3.6),digits,14,white)
	draw_circle(Vector2(285,y),76,Color(0.005,0.012,0.02,0.26))
	draw_arc(Vector2(285,y),76,0,TAU,96,Color(dim,0.22),1.0,true)
	_text(Vector2(285,y-85),"ATTITUDE",caption,11,Color(white,0.7))
	_text(Vector2(285,size.y-9),"世界水平参考",caption,11,Color(white,0.62))
	_gauge(Vector2(size.x-106,y),"ALTITUDE",maxf(0,car.position.y-0.515),100.0,"M")
	_draw_jets(Vector2(size.x-293,y-1))
	var mode := "接地 %d/4" % car.wheel_contacts if car.wheel_contacts>0 else "空中"
	if car.drift_amount>0.1 and car.tire_slip>1.0: mode = "漂移"
	_text(Vector2(size.x-193,size.y-15),"%s   ·   吸附 %s" % [mode,"ON" if car.adhesion else "OFF"],caption,12,Color(white,0.7))

func _draw_jets(center: Vector2) -> void:
	_text(center+Vector2(0,-84),"THRUST",caption,11,Color(white,0.7))
	var outline := PackedVector2Array([Vector2(-18,-61),Vector2(18,-61),Vector2(26,-43),Vector2(25,45),Vector2(19,59),Vector2(-19,59),Vector2(-25,45),Vector2(-26,-43)])
	for i in range(outline.size()): outline[i] += center
	draw_colored_polygon(outline,Color(0.005,0.012,0.02,0.32))
	outline.append(outline[0])
	draw_polyline(outline,dim,1.5,true)
	draw_polyline(PackedVector2Array([center+Vector2(-20,-30),center+Vector2(-15,-9),center+Vector2(15,-9),center+Vector2(20,-30),center+Vector2(-20,-30)]),dim,1.0,true)
	draw_rect(Rect2(center+Vector2(-15,8),Vector2(30,25)),Color(dim,0.26),false,1.0)
	draw_line(center+Vector2(-17,-58),center+Vector2(17,-58),Color(white,0.5),1.5,true)
	draw_line(center+Vector2(-17,56),center+Vector2(17,56),Color(1,0.24,0.3,0.6),1.5,true)
	for x in [-30.0,24.0]:
		for z in [-41.0,33.0]: draw_rect(Rect2(center+Vector2(x,z),Vector2(6,16)),Color(dim,0.48))
	for i in range(4):
		var mount: Vector3 = car.MOUNTS[i]
		_nozzle(center+Vector2(mount.x*30,mount.z*26),car.nozzle_visual_force(i),car.LIFT/4.0)
	for i in range(4):
		var mount: Vector3 = car.ROLL_MOUNTS[i]
		_nozzle(center+Vector2(signf(mount.x)*36,mount.z*26+(-7 if i<2 else 7)),car.roll_jet_forces[i] if car.roll_jet_forces[i].length()>100.0 else Vector3.ZERO,18000.0)
	_text(center+Vector2(0,77),"LIFT %03d %%" % int(car.lift_amount*100),digits,12,Color(white,0.72))

func _nozzle(at: Vector2, force: Vector3, maximum: float) -> void:
	var strength := clampf(force.length()/maximum,0,1)
	draw_circle(at,3.1,Color(dim,0.5))
	if strength<=0.001: return
	var shimmer := 0.85+0.15*sin(pulse*TAU)
	draw_circle(at,5.0+strength*3.0,Color(cyan,0.10*shimmer))
	draw_circle(at,2.5,Color(white,0.55+0.4*strength))
	var exhaust: Vector3 = -(car.global_basis.inverse()*force).normalized()
	var direction := Vector2(exhaust.x,exhaust.z)
	if direction.length()>0.15:
		direction = direction.normalized()
		var side := direction.orthogonal()*3.5
		var end := at+direction*(9.0+strength*18.0)*shimmer
		draw_colored_polygon(PackedVector2Array([at+side,at-side,end]),Color(cyan,0.3+strength*0.25))
		draw_line(at,end,Color(white,0.7),1.0,true)
	else:
		draw_arc(at,5.0+strength*3.0*shimmer,0,TAU,24,Color(cyan,0.5),1.0,true)
		if exhaust.y<0:
			draw_line(at+Vector2(-1.5,-1.5),at+Vector2(1.5,1.5),Color(0.07,0.12,0.16),1.0,true)
			draw_line(at+Vector2(-1.5,1.5),at+Vector2(1.5,-1.5),Color(0.07,0.12,0.16),1.0,true)
