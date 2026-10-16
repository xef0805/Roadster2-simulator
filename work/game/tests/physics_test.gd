extends SceneTree

const Lab = preload("res://main.gd")
var lab: Node3D
var vehicle: RigidBody3D
var failures: Array[String] = []
var reports: Array = []

func _initialize() -> void:
	call_deferred("_run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func place(at: Transform3D, input: Dictionary = {"throttle":0.0}) -> void:
	vehicle.test_controls = input
	vehicle.adhesion = true
	vehicle.request_reset(at)
	await frames(100)

func check(condition: bool, name: String, data: Dictionary = {}) -> void:
	reports.append({"name":name,"passed":condition,"data":data})
	print("PASS " if condition else "FAIL ",name," ",JSON.stringify(data))
	if not condition:
		failures.append(name)

func _run() -> void:
	lab = Lab.new()
	lab.testing = true
	root.add_child(lab)
	vehicle = lab.car
	await frames(180)
	check(vehicle.wheel_contacts==4 and absf(vehicle.position.y-0.5)<0.25,"four-wheel rest",{"position":vehicle.position,"contacts":vehicle.wheel_contacts})
	vehicle.test_controls = {"throttle":0.6}
	await frames(180)
	check(vehicle.linear_velocity.length()>8.0,"ground acceleration",{"speed":vehicle.linear_velocity.length()})
	vehicle.test_controls = {"brake":1.0}
	await frames(180)
	check(vehicle.linear_velocity.length()<4.0,"ground braking",{"speed":vehicle.linear_velocity.length()})
	for angle in [90.0,130.0]:
		await place(Lab.ramp_transform(deg_to_rad(angle),0.46))
		var start: Vector3 = vehicle.position
		await frames(240)
		check(vehicle.wheel_contacts>=3 and vehicle.position.distance_to(start)<0.8,"adhesion hold %.0f deg" % angle,{"drift":vehicle.position.distance_to(start),"contacts":vehicle.wheel_contacts,"up":vehicle.global_basis.y})
		vehicle.adhesion = false
		vehicle.test_controls = {"throttle":0.0}
		await frames(100)
		check(vehicle.linear_velocity.y < -2.0,"adhesion release %.0f deg" % angle,{"vy":vehicle.linear_velocity.y})
	await place(Transform3D(Basis.IDENTITY,Vector3(75,0.65,45)))
	vehicle.test_controls = {"lift":0.8}
	await frames(120)
	check(vehicle.position.y>3.0 and vehicle.wheel_contacts==0,"thrust takeoff",{"height":vehicle.position.y,"vy":vehicle.linear_velocity.y})
	vehicle.test_controls = {"lift":0.43,"roll":1.0}
	await frames(300)
	check(vehicle.spin_angle>4.0,"pilot-controlled roll",{"roll_radians":vehicle.spin_angle})
	vehicle.test_controls = {"lift":0.43}
	await frames(480)
	check(vehicle.global_basis.y.dot(Vector3.UP)>0.95,"bounded stabilization",{"up_y":vehicle.global_basis.y.y})
	vehicle.test_controls = {"throttle":0.0}
	vehicle.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,60,45)))
	await frames(3)
	var vy: float = vehicle.linear_velocity.y
	await frames(60)
	check(vehicle.linear_velocity.y<vy-3.0,"gravity after thrust release",{"before":vy,"after":vehicle.linear_velocity.y})
	for trial in range(3):
		await ramp_run(trial)
	for trial in range(3):
		await flight_run(trial)
	await place(Transform3D(Basis.IDENTITY,Vector3(75,22,45)))
	var lowest := 100.0
	for frame in range(1200):
		await physics_frame
		lowest = minf(lowest,vehicle.position.y)
	check(lowest>0.0 and vehicle.wheel_contacts==4 and vehicle.linear_velocity.length()<0.2,"hard landing without tunneling",{"min_y":lowest,"height":vehicle.position.y})
	await keyboard_run(false)
	await keyboard_run(true)
	await place(Transform3D(Basis.IDENTITY,Vector3(65,0.65,60)))
	vehicle.test_controls = {"throttle":0.5,"steer":0.7}
	await frames(180)
	check(vehicle.position.x>66.0 and (-vehicle.global_basis.z).x>0.1,"right steering changes trajectory",{"position":vehicle.position,"forward":-vehicle.global_basis.z})
	paused = true
	var paused_at: Vector3 = vehicle.position
	await frames(120)
	check(vehicle.position.distance_to(paused_at)<0.001,"pause freezes vehicle",{"drift":vehicle.position.distance_to(paused_at)})
	paused = false
	var report := {"engine":Engine.get_version_info().string,"physics_hz":Engine.physics_ticks_per_second,"tests":reports,"failures":failures}
	var f := FileAccess.open("user://physics-report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "))
	print("REPORT ",ProjectSettings.globalize_path("user://physics-report.json"))
	quit(0 if failures.is_empty() else 1)

func keys(throttle: bool, brake: bool, lift: bool, roll: bool) -> void:
	for pair in [["accelerate",throttle],["brake",brake],["lift",lift],["roll_right",roll]]:
		if pair[1]: Input.action_press(pair[0])
		else: Input.action_release(pair[0])

func keyboard_run(flight: bool) -> void:
	await place(Transform3D(Basis.IDENTITY,Vector3(36 if flight else -42,0.65,22 if flight else -30)))
	vehicle.test_controls.clear()
	var max_height := 0.0
	var overhang := false
	var airborne := false
	var landed := false
	var cleared := false
	var rolled := false
	var spin_start: float = vehicle.spin_angle
	for frame in range(6000):
		await physics_frame
		max_height = maxf(max_height,vehicle.position.y)
		if vehicle.wheel_contacts>1 and vehicle.global_basis.y.y< -0.15:
			overhang = true
		if (max_height>20.0 and vehicle.wheel_contacts==0) or (flight and vehicle.position.y>2.0):
			airborne = true
		var throttle := true
		var brake := false
		var lift := false
		var roll := false
		if flight:
			cleared = cleared or vehicle.position.z< -43.0
			throttle = not cleared
			brake = vehicle.position.z< -48.0
			if vehicle.position.z<13.0 and not cleared:
				lift = vehicle.linear_velocity.y < clampf((9.0-vehicle.position.y)*2.0,-3.0,9.0)
			if cleared and not rolled:
				roll = true
				lift = vehicle.linear_velocity.y<0.0
				rolled = vehicle.spin_angle-spin_start>TAU-0.35
			elif cleared:
				lift = vehicle.linear_velocity.y< -2.0
		elif airborne:
			throttle = false
			brake = vehicle.air_time>2.0
			lift = vehicle.linear_velocity.y< -2.0
		keys(throttle,brake,lift,roll)
		if airborne and (cleared if flight else overhang) and (rolled if flight else true) and vehicle.position.y<1.5 and vehicle.wheel_contacts>=3:
			landed = true
			break
	keys(false,false,false,false)
	vehicle.test_controls={"throttle":0.0}
	await frames(180)
	check(landed and vehicle.wheel_contacts==4,"binary keyboard "+("flight" if flight else "ramp"),{"landed":landed,"height":max_height,"position":vehicle.position,"cleared":cleared,"rolled":rolled,"overhang":overhang})

func ramp_run(trial: int) -> void:
	await place(Transform3D(Basis.IDENTITY,Vector3(-42,0.65,-30)))
	vehicle.test_controls = {"throttle":0.65}
	var max_height := 0.0
	var overhang := false
	var detached := false
	var landed := false
	var min_y := 100.0
	for frame in range(4800):
		await physics_frame
		max_height = maxf(max_height,vehicle.position.y)
		if vehicle.wheel_contacts>1 and vehicle.global_basis.y.y< -0.15:
			overhang = true
		if max_height>20.0 and vehicle.wheel_contacts==0:
			detached = true
			vehicle.test_controls = {"lift":clampf(0.425+(-vehicle.linear_velocity.y-2.0)*0.10,0.0,0.85),"brake":0.5 if vehicle.air_time>2.0 else 0.0}
		if detached:
			min_y = minf(min_y,vehicle.position.y)
			if vehicle.wheel_contacts>=3 and vehicle.position.y<1.5 and vehicle.global_basis.y.y>0.85:
				landed = true
				break
	vehicle.test_controls = {"throttle":0.0}
	await frames(120)
	check(overhang and detached and landed and vehicle.wheel_contacts==4,"ramp sequence %d" % (trial+1),{"height":max_height,"overhang":overhang,"detached":detached,"landed":landed,"position":vehicle.position,"min_y":min_y})

func flight_run(trial: int) -> void:
	await place(Transform3D(Basis.IDENTITY,Vector3(36,0.65,22)))
	var clear_obstacles := false
	var landed := false
	var roll_done := false
	var max_height := 0.0
	var initial_spin: float = vehicle.spin_angle
	var initial_obstacles: int = vehicle.obstacle_contacts
	for frame in range(2000):
		await physics_frame
		var z: float = vehicle.position.z
		var lift := 0.0
		var throttle := 0.65 if z> -43.0 else 0.0
		var brake := 0.0 if z> -48.0 else 0.5
		if z<10 and not clear_obstacles:
			lift = 1.0 if vehicle.linear_velocity.y<clampf((9.0-vehicle.position.y)*2.0,-3.0,9.0) else 0.0
		if z< -43.0:
			clear_obstacles = true
			lift = 1.0 if vehicle.linear_velocity.y< -2.0 else 0.0
		var roll := 0.0
		if z< -10.0 and not roll_done:
			roll = 1.0
			lift = 1.0 if vehicle.linear_velocity.y<0.0 else 0.0
			if vehicle.spin_angle-initial_spin>TAU-0.35:
				roll_done = true
		vehicle.test_controls = {"throttle":throttle,"brake":brake,"lift":lift,"roll":roll}
		max_height = maxf(max_height,vehicle.position.y)
		if clear_obstacles and roll_done and vehicle.position.y<1.4 and vehicle.wheel_contacts>=3:
			landed = true
			break
	vehicle.test_controls = {"throttle":0.0}
	await frames(120)
	check(clear_obstacles and roll_done and landed and vehicle.wheel_contacts==4 and vehicle.obstacle_contacts==initial_obstacles,"flight sequence %d" % (trial+1),{"height":max_height,"cleared":clear_obstacles,"rolled":roll_done,"landed":landed,"position":vehicle.position,"up":vehicle.global_basis.y,"spin":vehicle.spin_angle-initial_spin,"obstacle_contacts":vehicle.obstacle_contacts-initial_obstacles})
