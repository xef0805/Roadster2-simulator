extends SceneTree

const Lab = preload("res://main.gd")
var lab: Node3D
var car: RigidBody3D
var results: Array = []
var failed := false

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func check(ok: bool, name: String, data: Dictionary) -> void:
	results.append({"name":name,"passed":ok,"data":data})
	failed = failed or not ok
	print("PASS " if ok else "FAIL ",name," ",JSON.stringify(data))

func reset_air(input: Dictionary) -> void:
	car.test_controls = input
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,60,45)))
	await frames(3)

func run() -> void:
	lab = Lab.new()
	lab.testing = true
	root.add_child(lab)
	car = lab.car
	await reset_air({"lift":0.0})
	var y: float = (car.global_transform*car.center_of_mass).y
	var vy: float = car.linear_velocity.y
	await frames(120)
	var fall: float = y-(car.global_transform*car.center_of_mass).y
	var expected := -vy+0.5*9.81
	check(absf(fall-expected)<0.15,"one-second ballistic fall",{"fall_m":fall,"expected_m":expected,"vy":car.linear_velocity.y})
	car.test_controls = {"lift":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,0.65,45)))
	await frames(120)
	car.test_controls = {"lift":1.0}
	await frames(60)
	check(car.vertical_thrust>10000.0,"ground launch supplies measurable lift",{"force":car.vertical_thrust})
	car.test_controls = {"lift":0.0}
	await frames(2)
	check(car.lift_amount==0.0 and absf(car.current_force.y)<0.01,"release cuts lift immediately",{"remaining_lift":car.lift_amount,"upward_force":car.current_force.y})
	for direction in [-1.0,1.0]:
		await reset_air({"roll":direction})
		y = (car.global_transform*car.center_of_mass).y
		vy = car.linear_velocity.y
		await frames(120)
		fall = y-(car.global_transform*car.center_of_mass).y
		expected = -vy+0.5*9.81
		check(absf(fall-expected)<0.15,"roll preserves ballistic fall "+str(direction),{"fall_m":fall,"expected_m":expected})
		var forces = car.get("roll_jet_forces")
		var net := Vector3.ZERO
		var active := 0
		if forces!=null:
			for force in forces:
				net += force
				if force.length()>1.0: active+=1
		check(forces!=null and active==2 and net.length()<0.01,"opposed side jets "+str(direction),{"active":active,"net_force":net})
	var file := FileAccess.open("user://flight-feedback-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"tests":results,"passed":not failed},"  "))
	quit(1 if failed else 0)
