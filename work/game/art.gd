extends RefCounted

static func mat(color: Color, metal := 0.0, rough := 0.6, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m

static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = material
	parent.add_child(n)
	n.position = pos
	return n

static func beam(parent: Node3D, a: Vector3, b: Vector3, width: float, material: Material) -> MeshInstance3D:
	var n := box(parent, Vector3(width, width, a.distance_to(b)), (a + b) * 0.5, material)
	if a.distance_to(b) > 0.001:
		var up := Vector3.UP if abs((b-a).normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		n.look_at_from_position((a+b)*0.5, b, up)
	return n

static func mesh_from_faces(parent: Node3D, vertices: Array, faces: Array, material: Material, smooth := false) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	for f in faces:
		for j in range(1, f.size()-1):
			for k in [0, j, j+1]:
				st.add_vertex(vertices[f[k]])
	st.generate_normals()
	var n := MeshInstance3D.new()
	n.mesh = st.commit()
	n.material_override = material
	parent.add_child(n)
	return n

static func car(parent: Node3D, color: Color, detailed := false) -> Dictionary:
	var paint := mat(color,0.48,0.22)
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := mat(Color("10151b"),0.35,0.32)
	var glass := mat(Color("07131c"),0.68,0.14)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white := mat(Color("dcf4ff"),0.1,0.2,1.5)
	var red := mat(Color("ff1738"),0.1,0.3,1.8)
	# Rounded shoulders and real arch openings keep the coupe silhouette readable.
	var sections := [[-2.30,0.77,0.055],[-2.08,0.91,0.12],[-1.55,1.03,0.23],[-0.85,1.01,0.26],[0.10,1.00,0.27],[0.85,1.065,0.31],[1.45,1.065,0.34],[2.05,0.99,0.29],[2.20,0.89,0.22]]
	var vertices: Array = []
	var faces: Array = []
	var count := 92
	for i in range(count+1):
		var z := lerpf(-2.30,2.20,float(i)/count)
		var section := 0
		while section<sections.size()-2 and z>sections[section+1][0]: section+=1
		var a: Array = sections[section]
		var b: Array = sections[section+1]
		var t := smoothstep(float(a[0]),float(b[0]),z)
		var width := lerpf(float(a[1]),float(b[1]),t)
		var top := lerpf(float(a[2]),float(b[2]),t)
		var lower := -0.16
		for axle in [-1.48,1.48]:
			var dz: float = z-axle
			if absf(dz)<0.40: lower = maxf(lower,-0.25+sqrt(0.40*0.40-dz*dz))
		vertices.append_array([Vector3(-width,lower,z),Vector3(width,lower,z),Vector3(width,top-0.08,z),Vector3(width*0.86,top,z),Vector3(width*0.55,top+0.012,z),Vector3(-width*0.55,top+0.012,z),Vector3(-width*0.86,top,z),Vector3(-width,top-0.08,z)])
		if i>0:
			for j in range(8): faces.append([(i-1)*8+j,(i-1)*8+(j+1)%8,i*8+(j+1)%8,i*8+j])
	faces.append([7,6,5,4,3,2,1,0])
	var end := count*8
	faces.append([end,end+1,end+2,end+3,end+4,end+5,end+6,end+7])
	var body := mesh_from_faces(parent,vertices,faces,paint,true)
	body.name = "RoadsterBody"
	box(parent,Vector3(1.58,0.07,0.09),Vector3(0,-0.08,-2.27),dark)
	box(parent,Vector3(1.70,0.10,0.11),Vector3(0,-0.06,2.18),dark)
	for side in [-1.0,1.0]:
		# Two slim, swept front lamps rather than a rectangular full-width bar.
		beam(parent,Vector3(side*0.55,0.105,-2.17),Vector3(side*0.88,0.125,-1.98),0.035,dark)
		beam(parent,Vector3(side*0.56,0.12,-2.17),Vector3(side*0.86,0.14,-1.98),0.022,white)
		beam(parent,Vector3(side*1.005,-0.115,-0.92),Vector3(side*1.05,-0.10,0.93),0.055,dark)
		box(parent,Vector3(0.035,0.022,0.17),Vector3(side*1.015,0.215,0.18),dark)
		box(parent,Vector3(0.035,0.11,0.38),Vector3(side*1.065,0.04,0.95),dark)
		beam(parent,Vector3(side*0.78,0.35,-0.56),Vector3(side*1.06,0.36,-0.42),0.035,dark)
		var mirror := box(parent,Vector3(0.18,0.07,0.18),Vector3(side*1.06,0.38,-0.43),paint)
		mirror.rotation.y = side*0.22
	# Narrow red rear ribbon wraps into the rear shoulders.
	for i in range(20):
		var x0 := lerpf(-0.88,0.88,float(i)/20)
		var x1 := lerpf(-0.88,0.88,float(i+1)/20)
		beam(parent,Vector3(x0,0.25,2.215-0.08*pow(x0/0.88,2)),Vector3(x1,0.25,2.215-0.08*pow(x1/0.88,2)),0.027,red)
	for x in [-0.64,-0.32,0.0,0.32,0.64]:
		box(parent,Vector3(0.025,0.10,0.30),Vector3(x,-0.095,2.09),dark)
	box(parent,Vector3(1.61,0.025,0.15),Vector3(0,0.31,1.99),dark)
	var cabin := Node3D.new()
	cabin.name = "RoadsterGlassCanopy"
	parent.add_child(cabin)
	var canopy_sections := [[-0.96,0.79,0.28,0.285],[-0.73,0.75,0.28,0.47],[-0.46,0.70,0.29,0.68],[-0.20,0.66,0.29,0.79],[0.18,0.66,0.30,0.82],[0.48,0.69,0.31,0.78],[0.78,0.74,0.32,0.62],[1.04,0.79,0.33,0.43],[1.26,0.81,0.34,0.345]]
	var canopy_vertices: Array = []
	var canopy_faces: Array = []
	for i in range(45):
		var z := lerpf(-0.96,1.26,i/44.0)
		var section := 0
		while section<canopy_sections.size()-2 and z>canopy_sections[section+1][0]: section+=1
		var a: Array = canopy_sections[section]
		var b: Array = canopy_sections[section+1]
		var t := inverse_lerp(float(a[0]),float(b[0]),z)
		var width := lerpf(a[1],b[1],t)
		var belt := lerpf(a[2],b[2],t)
		var top := lerpf(a[3],b[3],t)
		for j in range(19):
			var u := lerpf(-1,1,j/18.0)
			var y := belt+(top-belt)*sqrt(maxf(0,1.0-pow(absf(u),6.0)))
			canopy_vertices.append(Vector3(u*width,y,z))
			if i>0 and j>0: canopy_faces.append([(i-1)*19+j-1,(i-1)*19+j,i*19+j,i*19+j-1])
	mesh_from_faces(cabin,canopy_vertices,canopy_faces,glass,true)
	for side in [-1.0,1.0]:
		beam(cabin,Vector3(side*0.79,0.28,-0.93),Vector3(side*0.55,0.71,-0.20),0.025,paint)
		beam(cabin,Vector3(side*0.56,0.69,0.48),Vector3(side*0.81,0.34,1.24),0.06,paint)
		beam(parent,Vector3(side*0.79,0.28,-0.93),Vector3(side*0.81,0.34,1.24),0.022,paint)
	var wheels: Array[Node3D] = []
	var rubber := mat(Color("07090c"),0.05,0.86)
	var alloy := mat(Color("8d99a5"),0.85,0.22)
	for p in [Vector3(-0.94,-0.25,-1.48),Vector3(0.94,-0.25,-1.48),Vector3(-0.94,-0.25,1.48),Vector3(0.94,-0.25,1.48)]:
		var wheel := Node3D.new()
		parent.add_child(wheel)
		wheel.position = p
		for data in [[0.34,0.25,rubber],[0.24,0.27,dark]]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = data[0]
			cyl.bottom_radius = data[0]
			cyl.height = data[1]
			cyl.radial_segments = 48
			var part := MeshInstance3D.new()
			part.mesh = cyl
			part.material_override = data[2]
			part.rotation.z = PI/2
			wheel.add_child(part)
		for side in [-1.0,1.0]:
			var rim := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = 0.205
			ring.outer_radius = 0.235
			rim.mesh = ring
			rim.material_override = alloy
			rim.rotation.z = PI/2
			rim.position.x = side*0.14
			wheel.add_child(rim)
			for i in range(5):
				var angle := TAU*i/5.0
				beam(wheel,Vector3(side*0.145,cos(angle)*0.045,sin(angle)*0.045),Vector3(side*0.145,cos(angle+0.18)*0.215,sin(angle+0.18)*0.215),0.028,alloy)
		wheels.append(wheel)
	var driver := {}
	if detailed:
		box(parent,Vector3(1.38,0.10,0.28),Vector3(0,0.38,-0.32),dark)
		box(parent,Vector3(0.34,0.13,0.025),Vector3(0.06,0.47,-0.41),mat(Color("166d83"),0.2,0.3,0.5))
		var torus := TorusMesh.new()
		torus.inner_radius = 0.12
		torus.outer_radius = 0.15
		var wheel_control := Node3D.new()
		parent.add_child(wheel_control)
		wheel_control.position = Vector3(-0.37,0.46,-0.24)
		var steering := MeshInstance3D.new()
		steering.mesh = torus
		steering.material_override = dark
		wheel_control.add_child(steering)
		steering.rotation.x = PI/2.5
		box(wheel_control,Vector3(0.24,0.025,0.025),Vector3.ZERO,alloy)
		driver = robot_driver(parent,wheel_control)
	return {"wheels":wheels,"cabin":cabin,"driver":driver}

static func robot_driver(parent: Node3D, wheel: Node3D) -> Dictionary:
	var armor := mat(Color("d8e1e7"),0.35,0.3)
	var joint := mat(Color("12191f"),0.2,0.5)
	var face := mat(Color("05090d"),0.6,0.12)
	box(parent,Vector3(0.42,0.10,0.45),Vector3(-0.37,0.07,0.52),joint)
	box(parent,Vector3(0.42,0.52,0.10),Vector3(-0.37,0.32,0.76),joint)
	box(parent,Vector3(0.21,0.12,0.18),Vector3(-0.37,0.23,0.48),joint)
	box(parent,Vector3(0.27,0.25,0.16),Vector3(-0.37,0.42,0.47),armor)
	box(parent,Vector3(0.17,0.12,0.03),Vector3(-0.37,0.43,0.375),joint)
	box(parent,Vector3(0.07,0.07,0.07),Vector3(-0.37,0.57,0.49),joint)
	var head := Node3D.new()
	parent.add_child(head)
	head.position = Vector3(-0.37,0.67,0.49)
	var shell := SphereMesh.new()
	shell.radius = 0.105
	shell.height = 0.22
	var helmet := MeshInstance3D.new()
	helmet.mesh = shell
	helmet.scale = Vector3(0.82,1,0.84)
	helmet.material_override = armor
	head.add_child(helmet)
	var visor := MeshInstance3D.new()
	visor.mesh = shell
	visor.scale = Vector3(0.73,0.80,0.24)
	visor.position = Vector3(0,0,-0.075)
	visor.material_override = face
	head.add_child(visor)
	var forearms := []
	var hands := []
	var elbows := []
	for side in [-1.0,1.0]:
		var shoulder := Vector3(-0.37+side*0.16,0.52,0.45)
		var elbow := Vector3(-0.37+side*0.19,0.36,0.02)
		var hand := wheel.position+Vector3(side*0.12,0,0)
		box(parent,Vector3(0.09,0.11,0.10),shoulder,armor)
		beam(parent,shoulder,elbow,0.075,armor)
		box(parent,Vector3(0.075,0.075,0.075),elbow,joint)
		forearms.append(beam(parent,elbow,hand,0.065,armor))
		hands.append(box(parent,Vector3(0.075,0.07,0.05),hand,armor))
		elbows.append(elbow)
		var hip := Vector3(-0.37+side*0.09,0.20,0.47)
		var knee := Vector3(-0.37+side*0.11,0.15,0.02)
		beam(parent,hip,knee,0.09,armor)
		box(parent,Vector3(0.085,0.085,0.085),knee,joint)
		beam(parent,knee,Vector3(knee.x,-0.01,-0.38),0.07,armor)
	return {"head":head,"forearms":forearms,"hands":hands,"elbows":elbows,"wheel":wheel}

static func loft(parent: Node3D, sections: Array, material: Material) -> void:
	var vertices: Array = []
	for s in sections:
		var z: float = s[0]
		var w: float = s[1]
		var bottom: float = s[2]
		var top: float = s[3]
		vertices.append_array([Vector3(-w*0.83,bottom,z),Vector3(w*0.83,bottom,z),Vector3(w,bottom+0.10,z),Vector3(w,top-0.09,z),Vector3(w*0.78,top,z),Vector3(-w*0.78,top,z),Vector3(-w,top-0.09,z),Vector3(-w,bottom+0.10,z)])
	var faces: Array = [[7,6,5,4,3,2,1,0]]
	for i in range(sections.size()-1):
		for j in range(8):
			faces.append([i*8+j,i*8+(j+1)%8,(i+1)*8+(j+1)%8,(i+1)*8+j])
	var end: int = (sections.size()-1)*8
	faces.append([end,end+1,end+2,end+3,end+4,end+5,end+6,end+7])
	mesh_from_faces(parent,vertices,faces,material)

static func parked_wheels(parent: Node3D, track: float, front: float, rear: float, radius: float, cap: Material) -> void:
	var rubber := mat(Color("07090c"),0.05,0.95)
	for x in [-track,track]:
		for z in [front,rear]:
			for data in [[radius,0.29,rubber],[radius*0.76,0.31,cap]]:
				var cyl := CylinderMesh.new()
				cyl.top_radius = data[0]
				cyl.bottom_radius = data[0]
				cyl.height = data[1]
				cyl.radial_segments = 20
				var wheel := MeshInstance3D.new()
				wheel.mesh = cyl
				wheel.material_override = data[2]
				wheel.position = Vector3(x,radius,z)
				wheel.rotation.z = PI/2
				parent.add_child(wheel)

static func tesla_vehicle(parent: Node3D, kind: String) -> Vector3:
	var dark := mat(Color("0b141c"),0.4,0.35)
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := mat(Color("0b202a"),0.65,0.16)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var silver := mat(Color("929ea6"),0.85,0.30)
	silver.cull_mode = BaseMaterial3D.CULL_DISABLED
	var white_light := mat(Color("d1f4ff"),0.1,0.2,1.2)
	var red_light := mat(Color("f51028"),0.1,0.3,1.0)
	if kind=="Cybercab":
		var gold := mat(Color("bba76f"),0.75,0.28)
		gold.cull_mode = BaseMaterial3D.CULL_DISABLED
		loft(parent,[[-2.2,0.80,0.28,0.63],[-1.65,0.96,0.25,0.79],[-0.6,0.97,0.25,0.85],[1.3,0.95,0.28,0.78],[2.15,0.78,0.35,0.68]],gold)
		loft(parent,[[-1.2,0.75,0.78,0.89],[-0.45,0.76,0.80,1.43],[0.6,0.77,0.80,1.45],[1.5,0.71,0.76,0.91]],glass)
		parked_wheels(parent,0.91,-1.38,1.38,0.35,gold)
		box(parent,Vector3(1.54,0.035,0.045),Vector3(0,0.63,-2.21),white_light)
		box(parent,Vector3(1.53,0.04,0.045),Vector3(0,0.69,2.16),red_light)
		return Vector3(2.0,1.5,4.5)
	if kind=="Cybertruck":
		loft(parent,[[-2.85,0.98,0.42,0.86],[-1.7,1.1,0.40,1.07],[0.3,1.10,0.40,1.08],[2.85,1.0,0.45,1.02]],silver)
		mesh_from_faces(parent,[Vector3(-0.98,1.04,-1.65),Vector3(0.98,1.04,-1.65),Vector3(0.94,1.94,-0.18),Vector3(-0.94,1.94,-0.18),Vector3(-0.98,1.10,1.52),Vector3(0.98,1.10,1.52)],[[0,3,2,1],[3,4,5,2]],glass)
		for side in [-1.0,1.0]:
			mesh_from_faces(parent,[Vector3(side*1.1,1.04,-1.65),Vector3(side*0.94,1.94,-0.18),Vector3(side*1.08,1.08,1.52)],[[0,1,2]],silver)
			mesh_from_faces(parent,[Vector3(side*1.102,1.13,-1.27),Vector3(side*0.954,1.83,-0.18),Vector3(side*1.085,1.15,1.24)],[[0,1,2]],glass)
			beam(parent,Vector3(side*1.11,0.50,-2.3),Vector3(side*1.11,0.50,2.35),0.10,dark)
		box(parent,Vector3(1.72,0.035,1.05),Vector3(0,1.04,2.20),dark)
		box(parent,Vector3(1.92,0.04,0.05),Vector3(0,0.9,-2.87),white_light)
		box(parent,Vector3(1.9,0.035,0.05),Vector3(0,1.0,2.88),red_light)
		parked_wheels(parent,1.06,-1.84,1.84,0.43,dark)
		return Vector3(2.3,2.0,5.8)
	if kind=="Semi":
		var white := mat(Color("dae1e5"),0.35,0.32)
		white.cull_mode = BaseMaterial3D.CULL_DISABLED
		loft(parent,[[-3.3,1.05,0.45,1.25],[-2.9,1.18,0.38,2.1],[-1.9,1.20,0.40,3.60],[-0.6,1.20,0.45,3.95],[0.3,1.18,0.48,3.95]],white)
		mesh_from_faces(parent,[Vector3(-1.13,1.7,-3.01),Vector3(1.13,1.7,-3.01),Vector3(1.11,2.8,-2.46),Vector3(-1.11,2.8,-2.46)],[[0,1,2,3]],glass)
		for side in [-1.0,1.0]:
			mesh_from_faces(parent,[Vector3(side*1.211,1.75,-2.8),Vector3(side*1.211,2.95,-2.00),Vector3(side*1.211,2.95,-0.50),Vector3(side*1.211,1.80,-0.50)],[[0,1,2,3]],glass)
		box(parent,Vector3(2.1,0.35,3.3),Vector3(0,0.77,1.3),dark)
		box(parent,Vector3(1.7,0.12,1.2),Vector3(0,1.02,1.5),silver)
		box(parent,Vector3(1.9,0.07,0.05),Vector3(0,0.98,-3.31),white_light)
		parked_wheels(parent,1.13,-2.1,1.28,0.49,silver)
		parked_wheels(parent,1.13,2.35,2.35,0.49,silver)
		return Vector3(2.6,4.0,6.8)
	var suv := kind=="Model Y"
	var paint := mat(Color("a52436") if suv else Color("1b608b"),0.65,0.25)
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	loft(parent,[[-2.35,0.75,0.28,0.60],[-1.85,0.94,0.25,0.77],[-0.9,0.99,0.25,0.88],[0.9,0.99,0.25,0.90],[1.9,0.92,0.29,0.79],[2.35,0.75,0.36,0.70]],paint)
	var roof := 1.66 if suv else 1.43
	loft(parent,[[-1.17,0.75,0.84,0.92],[-0.60,0.79,0.86,roof-0.1],[0.20,0.80,0.86,roof],[0.85,0.80,0.86,roof-0.09],[1.60,0.75,0.80,0.91]],glass)
	for side in [-1.0,1.0]:
		beam(parent,Vector3(side*0.98,0.83,-1.0),Vector3(side*0.96,0.84,1.48),0.035,paint)
		beam(parent,Vector3(side*0.8,0.89,0.3),Vector3(side*0.8,roof-0.03,0.3),0.045,dark)
		box(parent,Vector3(0.035,0.025,0.19),Vector3(side*0.997,0.82,0.0),silver)
		box(parent,Vector3(0.035,0.025,0.19),Vector3(side*0.997,0.82,1.05),silver)
	parked_wheels(parent,0.95,-1.48,1.48,0.36,silver)
	if suv:
		box(parent,Vector3(1.50,0.028,0.05),Vector3(0,0.66,-2.36),white_light)
		box(parent,Vector3(1.50,0.038,0.05),Vector3(0,0.73,2.36),red_light)
	else:
		for x in [-0.62,0.62]:
			box(parent,Vector3(0.35,0.045,0.08),Vector3(x,0.63,-2.30),white_light)
			box(parent,Vector3(0.44,0.06,0.06),Vector3(x,0.74,2.32),red_light)
	return Vector3(2.05,roof+0.05,4.8)

static func solid_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	body.position = pos
	box(body,size,Vector3.ZERO,material)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body
