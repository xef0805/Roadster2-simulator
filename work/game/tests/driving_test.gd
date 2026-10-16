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

func place(at: Transform3D) -> void:
	car.test_controls = {"throttle":0.0}
	car.adhesion = true
	car.request_reset(at)
	await frames(100)

func run() -> void:
	var lab := Lab.new()
	lab.testing = true
	root.add_child(lab)
	car = lab.car
	for x in [-42.7,-42.0,-41.3]:
		await place(Transform3D(Basis.IDENTITY,Vector3(x,0.65,22)))
		car.test_controls = {"throttle":1.0}
		var previous := 0.0
		var minimum_ratio := 1.0
		var overhang := false
		for frame in range(1200):
			await physics_frame
			var speed := car.linear_velocity.length()
			if previous>10.0 and car.position.y>0.8 and car.wheel_contacts>0:
				minimum_ratio = minf(minimum_ratio,speed/previous)
			previous = speed
			if car.global_basis.y.y< -0.65 and car.wheel_contacts>0:
				overhang = true
				break
		check(overhang and minimum_ratio>0.90,"ramp has no sudden stop at x="+str(x),{"minimum_speed_ratio":minimum_ratio,"reached_overhang":overhang,"speed":previous})
	var ranges := []
	for speed in [2.0,6.0,12.0]:
		# Place just beyond the edge, with a known tangent velocity and no controls.
		car.test_controls = {"throttle":0.0}
		car.adhesion = false
		car.request_reset(Lab.ramp_transform(deg_to_rad(150),0.65))
		await frames(3)
		car.linear_velocity = Vector3(0,sin(deg_to_rad(140)), -cos(deg_to_rad(140)))*speed
		await frames(1)
		var start: Vector3 = car.global_transform*car.center_of_mass
		var velocity := car.linear_velocity
		var at := start
		var contacts := 0
		for frame in range(720):
			await physics_frame
			at = car.global_transform*car.center_of_mass
			if at.y<2.1: break
			contacts += car.wheel_contacts
		var time := (velocity.y+sqrt(velocity.y*velocity.y+2.0*9.81*(start.y-at.y)))/9.81
		var expected := velocity.z*time
		var distance := at.z-start.z
		ranges.append(distance)
		check(contacts==0 and absf(distance-expected)<0.6,"unpowered departure at "+str(speed)+" m/s",{"horizontal_distance":distance,"ballistic_distance":expected,"contacts":contacts})
	check(ranges[0]<7.0 and ranges[2]>ranges[0]*4.0,"flight range follows departure speed",{"ranges_m":ranges})
	var grip := await turn(false)
	var drift := await turn(true)
	check(drift.peak_angle>grip.peak_angle+4.0 and drift.peak_angle>12.0 and drift.peak_angle<75.0,"handbrake creates controlled sideslip",{"normal":grip,"drift":drift})
	car.test_controls = {"throttle":0.2}
	await frames(300)
	var recovered := slip_angle()
	check(recovered<8.0 and car.wheel_contacts==4 and car.global_basis.y.y>0.95,"release restores tire grip",{"slip_degrees":recovered,"contacts":car.wheel_contacts,"up_y":car.global_basis.y.y})
	car.test_controls = {"drift":1.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,40,45)))
	await frames(60)
	check(car.drift_amount==0.0 and car.current_force.length()<0.01,"handbrake does not push airborne car",{"drift":car.drift_amount,"force":car.current_force})
	var file := FileAccess.open("user://driving-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)

func slip_angle() -> float:
	return rad_to_deg(atan2(absf(car.linear_velocity.dot(car.global_basis.x)),maxf(0.1,absf(car.forward_speed))))

func turn(drift: bool) -> Dictionary:
	await place(Transform3D(Basis.IDENTITY,Vector3(70,0.65,40)))
	car.linear_velocity = Vector3(0,0,-20)
	car.test_controls = {"throttle":0.35,"steer":0.65,"drift":1.0 if drift else 0.0}
	var peak := 0.0
	for frame in range(120):
		await physics_frame
		peak = maxf(peak,slip_angle())
	return {"peak_angle":peak,"speed":car.linear_velocity.length(),"up_y":car.global_basis.y.y}
