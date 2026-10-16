extends SceneTree

const Lab = preload("res://main.gd")
const Hud = preload("res://hud.gd")
var results := []
var passed := true

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for i in range(count): await physics_frame

func check(ok: bool, name: String, data: Dictionary) -> void:
	passed = passed and ok
	results.append({"passed":ok,"name":name,"data":data})
	print("PASS " if ok else "FAIL ",name," ",JSON.stringify(data))

func run() -> void:
	var lab := Lab.new()
	lab.testing = true
	root.add_child(lab)
	var car = lab.car
	car.test_controls = {"throttle":0.0}
	await frames(240)
	check(absf(car.g_force-1.0)<0.04,"stationary reads one G",{"g":car.g_force})
	var idle_force := 0.0
	for i in range(4): idle_force += car.nozzle_force(i).length()
	check(idle_force==0.0,"ground idle nozzles are dark",{"force":idle_force})
	car.test_controls = {"lift":1.0}
	await frames(60)
	var count := 0
	for i in range(4):
		if car.nozzle_force(i).y>1000.0: count+=1
	check(count==4 and car.g_force>2.1 and car.g_force<2.5,"lift lights four upward thrust nozzles",{"active":count,"g":car.g_force})
	car.test_controls = {"throttle":0.0}
	await frames(75)
	var release_force := 0.0
	for i in range(4): release_force+=car.nozzle_force(i).length()
	check(release_force<0.01 and car.g_force<0.04,"release removes lift indication",{"force":release_force,"g":car.g_force})
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,60,45)))
	car.test_controls = {"lift":1.0}
	await frames(90)
	check(car.g_force<0.04 and car.vertical_thrust==0.0,"high altitude Space reads ballistic zero G",{"g":car.g_force,"thrust":car.vertical_thrust})
	for direction in [-1.0,1.0]:
		car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,60,45)))
		car.test_controls = {"roll":direction}
		await frames(45)
		var active := []
		var net := Vector3.ZERO
		for i in range(4):
			var force: Vector3 = car.roll_jet_forces[i]
			if force.length()>100.0: active.append(i)
			net+=force
		var expected := [0,3] if direction>0 else [1,2]
		check(active==expected and net.length()<0.01,"roll jet map matches force pair "+str(direction),{"active":active,"net":net})
	car.freeze = true
	var hud := Hud.new()
	hud.car = car
	root.add_child(hud)
	hud.size = Vector2(1600,900)
	for pose in [Vector3.ZERO,Vector3(PI/2,0,0),Vector3(PI,0,0),Vector3(0,0,PI/2),Vector3(0,1.3,-PI/2)]:
		car.global_basis = Basis.from_euler(pose)
		lab.camera.rotation = Vector3(0.4,1.1,0.9)
		await process_frame
		await process_frame
		var match_value := absf(hud.attitude_car.basis.get_rotation_quaternion().dot(car.global_basis.get_rotation_quaternion()))
		check(match_value>0.9999,"miniature keeps world attitude "+str(pose),{"quaternion_match":match_value})
	var file := FileAccess.open("user://hud-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)
