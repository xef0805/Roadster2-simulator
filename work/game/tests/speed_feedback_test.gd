extends SceneTree
const Lab = preload("res://main.gd")
var car: RigidBody3D
var results := []
var passed := true

func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await physics_frame
func check(ok: bool, name: String, data: Dictionary) -> void:
	passed = passed and ok
	results.append({"passed":ok,"name":name,"data":data})
	print("PASS " if ok else "FAIL ",name," ",JSON.stringify(data))
func place(speed: float) -> void:
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,0.65,150)))
	await frames(100)
	car.linear_velocity = Vector3(0,0,-speed)
	await frames(1)
func run() -> void:
	var lab := Lab.new()
	lab.testing = true
	root.add_child(lab)
	car = lab.car
	await place(20.0)
	var start := car.linear_velocity.length()
	await frames(120)
	var coast := car.linear_velocity.length()
	check(coast>18.0 and coast<start,"release throttle coasts instead of emergency braking",{"start_m_s":start,"after_one_second_m_s":coast})
	var acceleration := []
	for speed in [20.0,60.0]:
		await place(speed)
		car.test_controls = {"throttle":1.0}
		start = car.linear_velocity.length()
		await frames(60)
		acceleration.append((car.linear_velocity.length()-start)/0.5)
	check(acceleration[1]>0 and acceleration[1]<acceleration[0]*0.6,"motor acceleration tapers with speed",{"acceleration_m_s2":acceleration})
	await place(20.0)
	car.test_controls = {"brake":1.0}
	await frames(360)
	check(absf(car.forward_speed)<0.3,"holding brake stops without automatic reverse",{"forward_speed":car.forward_speed})
	car.test_controls = {"throttle":0.0}
	await frames(6)
	car.test_controls = {"brake":1.0}
	await frames(120)
	check(car.forward_speed< -1.0 and car.forward_speed> -10.0,"press brake again to reverse",{"forward_speed":car.forward_speed})
	var file := FileAccess.open("user://speed-feedback-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)
