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

func place(height: float) -> void:
	car.test_controls = {"lift":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(75,height,45)))
	await frames(120 if height<1.0 else 3)

func run() -> void:
	var lab := Lab.new()
	lab.testing = true
	root.add_child(lab)
	car = lab.car
	await place(0.65)
	car.test_controls = {"lift":1.0}
	var peak := 0.0
	var boosts_above_range := 0
	var late_peak := 0.0
	for i in range(1800):
		await physics_frame
		peak = maxf(peak,car.position.y)
		if car.ground_clearance>=car.LIFT_RANGE and car.vertical_thrust>0.01: boosts_above_range+=1
		if i>960: late_peak = maxf(late_peak,car.position.y)
	check(peak>3.0 and peak<12.0 and boosts_above_range==0,"held Space has a bounded ballistic jump",{"peak_m":peak,"boosts_above_range":boosts_above_range})
	check(late_peak<1.0 and car.wheel_contacts==4,"holding Space settles without automatic relaunch",{"late_peak":late_peak,"contacts":car.wheel_contacts})
	car.test_controls = {"lift":0.0}
	await frames(30)
	car.test_controls = {"lift":1.0}
	await frames(60)
	check(car.position.y>1.5 and car.linear_velocity.y>2.0,"release then press rearms a ground jump",{"height":car.position.y,"vy":car.linear_velocity.y})
	car.test_controls = {"lift":0.0}
	await frames(2)
	check(car.vertical_thrust==0.0,"release immediately cuts actual vertical force",{"force":car.vertical_thrust})
	await place(60.0)
	var y: float = car.position.y
	for i in range(120):
		car.test_controls = {"lift":1.0 if (i/6)%2==0 else 0.0}
		await physics_frame
	check(car.vertical_thrust==0.0 and car.position.y<y-4.8 and car.linear_velocity.y< -9.5,"repeated air presses cannot boost or hover",{"fall_m":y-car.position.y,"vy":car.linear_velocity.y})
	var impacts := []
	for cushioning in [false,true]:
		await place(22.0)
		car.test_controls = {"lift":1.0 if cushioning else 0.0}
		var max_bounce := 0.0
		var max_near_vy := 0.0
		var impact := 0.0
		var has_contact := false
		var min_y := 100.0
		for i in range(1200):
			await physics_frame
			min_y = minf(min_y,car.position.y)
			if car.position.y<1.0: max_near_vy = maxf(max_near_vy,-car.linear_velocity.y)
			if car.wheel_contacts>0 and not has_contact:
				impact = car.last_landing
				has_contact = true
			if has_contact: max_bounce = maxf(max_bounce,car.position.y)
		impacts.append(impact)
		check(has_contact and min_y>0.0 and car.wheel_contacts==4 and (not cushioning or max_bounce<1.2),"cushioned landing" if cushioning else "unpowered hard landing",{"first_contact_speed":impact,"speed_below_1m":max_near_vy,"min_y":min_y,"bounce_height":max_bounce})
	check(impacts[1]<3.0 and impacts[1]<impacts[0]*0.3,"near-ground cushion reduces impact without reversing descent",{"unpowered":impacts[0],"cushioned":impacts[1]})
	var f := FileAccess.open("user://ground-jet-report.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)
