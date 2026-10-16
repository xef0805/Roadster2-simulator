extends SceneTree

const Lab = preload("res://main.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var lab := Lab.new()
	lab.testing = true
	root.add_child(lab)
	var results := []
	var passed := true
	for entry in [[0.65,-30.0],[1.0,-30.0],[1.0,22.0]]:
		for trial in range(3):
			var report: Dictionary = await drive_ramp(lab.car,entry[0],entry[1])
			report["throttle"] = entry[0]
			report["start_z"] = entry[1]
			report["trial"] = trial+1
			results.append(report)
			passed = passed and report.passed
			print("RAMP DEPARTURE ",JSON.stringify(report))
	var file := FileAccess.open("user://ramp-departure-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"tests":results},"  "))
	quit(0 if passed else 1)

func drive_ramp(car: RigidBody3D, throttle: float, start_z: float) -> Dictionary:
	car.test_controls = {"throttle":0.0}
	car.request_reset(Transform3D(Basis.IDENTITY,Vector3(-42,0.65,start_z)))
	for frame in range(100): await physics_frame
	if throttle==1.0:
		car.test_controls.clear()
		Input.action_press("accelerate")
	else:
		car.test_controls = {"throttle":throttle}
	var on_overhang := false
	var departed := false
	var inverted := false
	var upright := false
	var progress := 0.0
	var last_angle := 0.0
	var frames_in_air := 0
	var early_rate := 100.0
	var min_progress := 0.0
	var takeoff_rate := 0.0
	for frame in range(1800):
		await physics_frame
		if car.wheel_contacts>0 and car.global_basis.y.y< -0.5:
			on_overhang = true
		if on_overhang and car.wheel_contacts==0 and not departed:
			departed = true
			takeoff_rate = car.angular_velocity.x
			last_angle = atan2(car.global_basis.y.z,car.global_basis.y.y)
			Input.action_release("accelerate")
			car.test_controls = {"throttle":0.0}
		if departed:
			frames_in_air += 1
			var angle := atan2(car.global_basis.y.z,car.global_basis.y.y)
			progress += wrapf(angle-last_angle,-PI,PI)
			min_progress = minf(min_progress,progress)
			last_angle = angle
			if frames_in_air<60:
				early_rate = minf(early_rate,car.angular_velocity.x)
			inverted = inverted or car.global_basis.y.y< -0.97
			if progress>PI and car.global_basis.y.y>0.95:
				upright = true
				break
			if frames_in_air>720: break
	# Measure the trajectory: allow sub-degree contact jitter, not reverse leveling.
	var passed := departed and inverted and upright and min_progress>deg_to_rad(-0.5)
	var report := {"passed":passed,"departed":departed,"fully_inverted":inverted,"upright_after_forward_flip":upright,"takeoff_rate":takeoff_rate,"min_first_half_second_rate":early_rate,"minimum_rotation_degrees":rad_to_deg(min_progress),"forward_rotation_degrees":rad_to_deg(progress),"elapsed_air_seconds":frames_in_air/120.0}
	Input.action_release("accelerate")
	return report
