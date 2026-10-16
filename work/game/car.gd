extends RigidBody3D

const Art = preload("res://art.gd")
const MASS := 1400.0
const G := 9.81
const RADIUS := 0.34
const REST := 0.40
const SPRING := 46000.0
const DAMPER := 4400.0
const DRIVE := 28000.0
const MOTOR_POWER := 550000.0
const LIFT := MASS * G * 2.35
const CUSHION_LIFT := MASS * G * 10.0
const LIFT_RANGE := 6.0
const MOUNTS := [Vector3(-0.94,0.15,-1.48),Vector3(0.94,0.15,-1.48),Vector3(-0.94,0.15,1.48),Vector3(0.94,0.15,1.48)]
const ROLL_MOUNTS := [Vector3(-1.035,0.18,-1.78),Vector3(1.035,0.18,-1.78),Vector3(-1.035,-0.12,-1.78),Vector3(1.035,-0.12,-1.78)]
const ROLL_JET_SEPARATION := 0.30

var adhesion := true
var wheel_contacts := 0
var road_normal := Vector3.UP
var lift_amount := 0.0
var forward_speed := 0.0
var impact_speed := 0.0
var last_landing := 0.0
var wheel_lengths := [REST,REST,REST,REST]
var controls := {"throttle":0.0,"brake":0.0,"steer":0.0,"roll":0.0,"lift":0.0,"drift":0.0}
var drift_amount := 0.0
var tire_slip := 0.0
var motor_amount := 0.0
var reverse_drive := false
var brake_was_held := false
var cockpit_audio := false
var audio_muted := false
var audio_view_gain := 0.0
var downwash_strength := 0.0
var ground_clearance := INF
var launch_time := 0.0
var launch_armed := true
var vertical_thrust := 0.0
var test_controls: Dictionary = {}
var wheel_visuals: Array[Node3D] = []
var cabin: Node3D
var driver: Dictionary = {}
var cockpit_mirror: Node3D
var mirror_view: SubViewport
var mirror_camera: Camera3D
var jet_nodes: Array[GPUParticles3D] = []
var jet_cores: Array[MeshInstance3D] = []
var roll_jet_nodes: Array[GPUParticles3D] = []
var roll_jet_cores: Array[MeshInstance3D] = []
var roll_jet_forces: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var dust: GPUParticles3D
var landing_dust: GPUParticles3D
var dust_cooldown := 0.0
var jet_audio: AudioStreamPlayer3D
var impact_audio: AudioStreamPlayer3D
var motor_audio: AudioStreamPlayer3D
var road_audio: AudioStreamPlayer3D
var skid_audio: AudioStreamPlayer3D
var tire_smoke: Array[GPUParticles3D] = []
var reset_target := Transform3D(Basis.IDENTITY,Vector3(-42,0.65,26))
var reset_pending := false
var last_contacts := 0
var descending_speed := 0.0
var air_time := 0.0
var spin_angle := 0.0
var current_force := Vector3.ZERO
var current_torque := Vector3.ZERO
var visual_enabled := true
var pending_impact := false
var obstacle_contacts := 0
var ramp_flip_active := false
var ramp_flip_axis := Vector3.RIGHT
var ramp_flip_remaining := 0.0
var ramp_flip_rate := 0.0
var road_curvature := 0.0
var g_force := 1.0
var telemetry_velocity := Vector3.ZERO
var telemetry_ready := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0,-0.08,0)
	continuous_cd = true
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.15
	contact_monitor = true
	max_contacts_reported = 8
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.76,0.35,3.95)
	col.shape = shape
	col.position.y = 0.04
	add_child(col)
	if visual_enabled:
		var visual := Art.car(self,Color("e6edf1"),true)
		wheel_visuals = visual.wheels
		cabin = visual.cabin
		driver = visual.driver
		_make_cockpit_mirror()
		_make_effects()
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(0,0.22,-2.25)
		lamp.spot_range = 38
		lamp.spot_angle = 34
		lamp.light_color = Color("b9dfff")
		lamp.light_energy = 2.0
		add_child(lamp)

func request_reset(at: Transform3D) -> void:
	reset_target = at
	reset_pending = true

func _read_controls() -> void:
	if not test_controls.is_empty():
		for key in controls:
			controls[key] = float(test_controls.get(key,0.0))
	else:
		controls.throttle = Input.get_action_strength("accelerate")
		controls.brake = Input.get_action_strength("brake")
		controls.steer = Input.get_axis("left","right")
		controls.roll = Input.get_axis("roll_left","roll_right")
		controls.lift = Input.get_action_strength("lift")
		controls.drift = Input.get_action_strength("drift")

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if reset_pending:
		state.transform = reset_target
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		reset_pending = false
		last_contacts = 0
		air_time = 0.0
		lift_amount = 0.0
		ramp_flip_active = false
		road_curvature = 0.0
		drift_amount = 0.0
		tire_slip = 0.0
		motor_amount = 0.0
		reverse_drive = false
		brake_was_held = false
		launch_time = 0.0
		launch_armed = true
		vertical_thrust = 0.0
		telemetry_ready = false
		g_force = 0.0
	_read_controls()
	for contact in range(state.get_contact_count()):
		var other := state.get_contact_collider_object(contact)
		if other!=null and other.has_meta("obstacle"):
			obstacle_contacts += 1
	var dt := state.step
	var basis := state.transform.basis.orthonormalized()
	var up := basis.y
	var forward := -basis.z
	var velocity := state.linear_velocity
	if telemetry_ready:
		var proper_acceleration := (velocity-telemetry_velocity)/dt-Vector3.DOWN*G
		g_force = lerpf(g_force,proper_acceleration.length()/G,1.0-exp(-dt*9.0))
	telemetry_velocity = velocity
	telemetry_ready = true
	forward_speed = velocity.dot(forward)
	motor_amount = move_toward(motor_amount,float(controls.throttle),dt*(4.0 if float(controls.throttle)>motor_amount else 12.0))
	var braking := float(controls.brake)>0.05
	if braking and not brake_was_held:
		reverse_drive = last_contacts>0 and absf(forward_speed)<0.5
	if not braking or float(controls.throttle)>0.05:
		reverse_drive = false
	brake_was_held = braking
	var ground_query := PhysicsRayQueryParameters3D.create(state.transform.origin,state.transform.origin+Vector3.DOWN*(LIFT_RANGE+0.515),1,[get_rid()])
	var nearby := state.get_space_state().intersect_ray(ground_query)
	ground_clearance = maxf(0.0,state.transform.origin.distance_to(nearby.position)-0.515) if not nearby.is_empty() and nearby.normal.y>0.35 else INF
	var lift_input := float(controls.lift)
	if lift_input<0.05:
		launch_time = 0.0
		if last_contacts>0: launch_armed = true
	if last_contacts==0 and velocity.y< -1.2 and launch_time<=0.0 and lift_input>0.05:
		launch_armed = false
	if launch_armed and last_contacts>0 and ground_clearance<0.8 and lift_input>0.05:
		launch_time = 0.8
		launch_armed = false
	launch_time = maxf(0.0,launch_time-dt)
	var lift_target := 0.0
	var lift_limit := LIFT
	if ground_clearance<LIFT_RANGE:
		if launch_time>0.0:
			lift_target = lift_input*(1.0-smoothstep(3.0,5.0,ground_clearance))
		elif velocity.y< -1.2:
			# Brake over the remaining distance, without reversing descent into another jump.
			var deceleration := (velocity.y*velocity.y-1.2*1.2)/(2.0*maxf(ground_clearance-0.25,0.2))
			lift_limit = minf(CUSHION_LIFT,MASS*(G+deceleration))
			lift_target = lift_input
	lift_amount = move_toward(lift_amount,lift_target,dt*20.0) if lift_target>0.0 else 0.0
	vertical_thrust = lift_limit*lift_amount
	roll_jet_forces.fill(Vector3.ZERO)
	var previous_normal := road_normal
	var drift_target := float(controls.drift) if last_contacts>0 and previous_normal.y>0.65 else 0.0
	drift_amount = move_toward(drift_amount,drift_target,dt*(5.0 if drift_target>drift_amount else 2.5))
	wheel_contacts = 0
	tire_slip = 0.0
	var normal_sum := Vector3.ZERO
	var front_normal := Vector3.ZERO
	var rear_normal := Vector3.ZERO
	var query := PhysicsRayQueryParameters3D.new()
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var space := state.get_space_state()
	for i in range(4):
		var arm: Vector3 = basis * MOUNTS[i]
		query.from = state.transform.origin + arm
		query.to = query.from - up * (REST+RADIUS+0.12)
		var hit := space.intersect_ray(query)
		wheel_lengths[i] = REST
		if hit.is_empty():
			continue
		var n: Vector3 = hit.normal
		if n.dot(up) < 0.35:
			continue
		var length: float = clampf(query.from.distance_to(hit.position)-RADIUS,0.02,REST+0.12)
		wheel_lengths[i] = length
		wheel_contacts += 1
		normal_sum += n
		if i<2: front_normal += n
		else: rear_normal += n
		var point_velocity: Vector3 = velocity + state.angular_velocity.cross(arm)
		var compression := REST-length
		# Progressive bump stops support the centripetal load before the chassis scrapes.
		var spring_force := compression*SPRING+2000000.0*pow(maxf(compression-0.22,0.0),2.0)
		var normal_load: float = clampf(spring_force-point_velocity.dot(n)*DAMPER,0.0,60000.0)
		state.apply_force(n*normal_load,arm)
		var suction := 0.0
		if adhesion and lift_amount<0.10:
			suction = MASS*G*0.65*clampf((1.0-n.y)/0.65,0.0,1.0)
			state.apply_force(-n*suction,arm)
		var steer_angle: float = -float(controls.steer)*0.46/(1.0+abs(forward_speed)*0.025) if i<2 else 0.0
		var tire_forward: Vector3 = forward.rotated(up,steer_angle).slide(n).normalized()
		var tire_right: Vector3 = tire_forward.cross(n).normalized()
		var v_long := point_velocity.dot(tire_forward)
		var v_side := point_velocity.dot(tire_right)
		var longitudinal: float = motor_amount*minf(DRIVE,MOTOR_POWER/maxf(absf(forward_speed),1.0))/4.0
		if float(controls.brake)>0.0:
			if reverse_drive:
				longitudinal -= DRIVE*0.40/4.0*float(controls.brake)*clampf((9.0+v_long)/3.0,0.0,1.0)
			else:
				longitudinal -= clampf(v_long*MASS*4.0/4.0,-DRIVE*0.6,DRIVE*0.6)*float(controls.brake)
		elif float(controls.throttle)<0.01:
			longitudinal -= clampf(v_long*MASS*0.15/4.0,-MASS*0.65/4.0,MASS*0.65/4.0)
		if adhesion and n.y<0.8 and absf(forward_speed)<0.5 and motor_amount<0.01 and not reverse_drive:
			longitudinal -= Vector3.DOWN.dot(tire_forward)*MASS*G/4.0
		var rear_drift := drift_amount if i>=2 else 0.0
		if i>=2:
			longitudinal *= 1.0-rear_drift*0.6
			longitudinal -= signf(v_long)*minf(absf(v_long)*MASS/4.0,2500.0)*rear_drift
			tire_slip = maxf(tire_slip,absf(v_side))
		var side_grip := lerpf(6.5,2.4,rear_drift)
		var tire_force: Vector3 = tire_forward*longitudinal - tire_right*v_side*MASS*side_grip/4.0
		tire_force = tire_force.limit_length(maxf(normal_load,500.0)*lerpf(1.8,1.4,rear_drift))
		state.apply_force(tire_force,arm)
	road_normal = normal_sum.normalized() if wheel_contacts>0 else Vector3.UP
	current_force = Vector3.UP*vertical_thrust
	current_torque = Vector3.ZERO
	if wheel_contacts>0:
		ramp_flip_active = false
		var tilt_error := Vector3.ZERO
		if front_normal.length_squared()>0.1 and rear_normal.length_squared()>0.1:
			road_curvature = rear_normal.signed_angle_to(front_normal,basis.x)/2.96
			tilt_error = up.cross(road_normal)
		# Follow surface rotation; the last axle leaving must not pull the nose backwards.
		var surface_rotation := basis.x*forward_speed*road_curvature
		current_torque = tilt_error*MASS*38.0-(state.angular_velocity-surface_rotation).slide(road_normal)*MASS*4.5
		air_time = 0.0
		if last_contacts==0 and descending_speed>1.5:
			last_landing = descending_speed
			impact_speed = descending_speed
			pending_impact = true
	else:
		air_time += dt
		if last_contacts>0 and previous_normal.y< -0.45 and forward_speed>0.2:
			ramp_flip_axis = basis.x
			ramp_flip_remaining = fposmod(up.signed_angle_to(Vector3.UP,ramp_flip_axis),TAU)
			ramp_flip_rate = clampf(maxf(state.angular_velocity.dot(ramp_flip_axis),forward_speed*road_curvature),0.0,1.7)
			ramp_flip_active = true
		if ramp_flip_active:
			ramp_flip_remaining -= state.angular_velocity.dot(ramp_flip_axis)*dt
			if absf(ramp_flip_remaining)<0.04 and absf(state.angular_velocity.dot(ramp_flip_axis))<0.6:
				ramp_flip_active = false
		var forward_horizontal := forward.slide(Vector3.UP)
		current_force += forward_horizontal*float(controls.throttle)*MASS*6.0
		var horizontal_velocity := velocity.slide(Vector3.UP)
		if horizontal_velocity.length()>0.05:
			current_force -= horizontal_velocity.normalized()*minf(float(controls.brake)*MASS*8.0,horizontal_velocity.length()*MASS/dt)
		# Stabilization is a bounded torque; pilot roll input overrides leveling.
		var roll_input := float(controls.roll)
		if absf(roll_input)>0.05:
			current_torque += forward*(roll_input*MASS*7.0-state.angular_velocity.dot(forward)*MASS*2.8)
			spin_angle += absf(state.angular_velocity.dot(forward))*dt
			var pitch_axis := basis.x
			if not ramp_flip_active:
				current_torque -= pitch_axis*state.angular_velocity.dot(pitch_axis)*MASS*2.0
		elif not ramp_flip_active:
			var tilt_axis := up.cross(Vector3.UP)
			var angle := acos(clampf(up.dot(Vector3.UP),-1.0,1.0))
			if tilt_axis.length()<0.05 and up.y<0.0:
				tilt_axis = forward
			if tilt_axis.length()>0.001:
				current_torque += tilt_axis.normalized()*angle*MASS*5.2
			current_torque -= state.angular_velocity.slide(Vector3.UP)*MASS*3.8
		if ramp_flip_active:
			# Continue around the ramp's pitch axis instead of leveling backwards.
			var desired_rate := clampf(ramp_flip_remaining*2.0,-0.7,ramp_flip_rate)
			current_torque += ramp_flip_axis*(desired_rate-state.angular_velocity.dot(ramp_flip_axis))*MASS*4.8
		current_torque += Vector3.UP*(-float(controls.steer)*MASS*4.0-state.angular_velocity.y*MASS*1.8)
		current_torque = current_torque.limit_length(MASS*12.0)
	state.apply_central_force(current_force)
	if wheel_contacts==0:
		# Opposite horizontal forces at different heights make a roll couple.
		# Their net force is zero, including when the car is inverted.
		var roll_torque := current_torque.dot(forward)
		var pair := [0,3] if roll_torque>=0.0 else [1,2]
		var side_force := basis.x*roll_torque/ROLL_JET_SEPARATION
		roll_jet_forces[pair[0]] = side_force
		roll_jet_forces[pair[1]] = -side_force
		for i in pair:
			state.apply_force(roll_jet_forces[i],basis*ROLL_MOUNTS[i])
		state.apply_torque(current_torque-forward*roll_torque)
	else:
		state.apply_torque(current_torque)
	state.apply_central_force(-velocity*velocity.length()*0.8)
	if wheel_contacts>0:
		state.apply_central_force(-velocity.normalized()*minf(MASS*G*0.015,velocity.length()*MASS/dt))
	descending_speed = maxf(0.0,-velocity.y)
	last_contacts = wheel_contacts

func nozzle_force(index: int) -> Vector3:
	if wheel_contacts>0 and lift_amount<=0.05:
		return Vector3.ZERO
	var arm: Vector3 = global_basis*MOUNTS[index]
	var other_torque := current_torque+global_basis.z*current_torque.dot(-global_basis.z)
	var force := current_force/4.0+other_torque.cross(arm)/16.0
	return force if force.length()/(LIFT/4.0)>0.025 else Vector3.ZERO

func nozzle_visual_force(index: int) -> Vector3:
	# High-air exhaust stays visible without adding lift to the rigid body.
	var force := nozzle_force(index)
	if float(controls.lift)>0.05 and vertical_thrust<LIFT*0.22:
		force += Vector3.UP*(LIFT*0.22-vertical_thrust)*float(controls.lift)/4.0
	return force

func _process(delta: float) -> void:
	if not visual_enabled:
		return
	if not driver.is_empty():
		driver.head.visible = true
		var turn := Basis(Vector3(0,cos(PI/2.5),sin(PI/2.5)),-float(controls.steer)*0.55)
		driver.wheel.basis = turn
		for i in range(2):
			var hand: Vector3 = driver.wheel.position+turn*Vector3(-0.12 if i==0 else 0.12,0,0)
			driver.hands[i].position = hand
			var elbow: Vector3 = driver.elbows[i]
			var arm: MeshInstance3D = driver.forearms[i]
			(arm.mesh as BoxMesh).size.z = elbow.distance_to(hand)
			arm.position = (elbow+hand)*0.5
			arm.basis = Basis.looking_at(hand-elbow,Vector3.UP)
	cockpit_mirror.visible = cockpit_audio
	mirror_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if cockpit_audio else SubViewport.UPDATE_DISABLED
	if cockpit_audio:
		mirror_camera.position = global_transform*Vector3(0,0.80,-0.56)
		mirror_camera.look_at(global_transform*Vector3(-0.37,0.65,0.49),global_basis.y)
	for i in range(wheel_visuals.size()):
		wheel_visuals[i].position.y = 0.15-float(wheel_lengths[i])
		wheel_visuals[i].rotation.y = -float(controls.steer)*0.4 if i<2 else 0.0
	for i in range(jet_nodes.size()):
		var jet := jet_nodes[i]
		var force := nozzle_visual_force(i)
		var strength := force.length()/(LIFT/4.0)
		jet.emitting = strength>0.025
		jet.amount_ratio = clampf(strength,0.05,1.0)
		jet_cores[i].visible = jet.emitting
		if force.length()>1.0:
			jet.global_basis = Basis(Quaternion(Vector3.UP,-force.normalized()))
		var plume_length := 0.6+minf(strength,1.2)*2.4
		jet_cores[i].scale = Vector3.ONE*0.7+Vector3(0.3,0,0.3)*minf(strength,1.0)
		jet_cores[i].scale.y = plume_length
		jet_cores[i].position.y = plume_length*0.5
		var pmat := jet.process_material as ParticleProcessMaterial
		pmat.initial_velocity_min = 12.0+strength*4.0
		pmat.initial_velocity_max = 18.0+strength*6.0
	for i in range(roll_jet_nodes.size()):
		var jet := roll_jet_nodes[i]
		var force := roll_jet_forces[i]
		var active := force.length()>100.0
		var strength := clampf(force.length()/18000.0,0.0,1.0)
		jet.emitting = active
		jet.amount_ratio = clampf(strength,0.18,1.0)
		roll_jet_cores[i].visible = active
		if active:
			jet.global_basis = Basis(Quaternion(Vector3.UP,-force.normalized()))
			var plume_length := 0.65+strength*1.65
			roll_jet_cores[i].scale = Vector3(1.0,plume_length,1.0)
			roll_jet_cores[i].position.y = plume_length*0.5
	var cast := PhysicsRayQueryParameters3D.create(global_position,global_position+Vector3.DOWN*7.0,1,[get_rid()])
	var ground := get_world_3d().direct_space_state.intersect_ray(cast)
	dust_cooldown = maxf(0.0,dust_cooldown-delta)
	downwash_strength = 0.0
	var wash_position := Vector3.ZERO
	var wash_normal := Vector3.ZERO
	for i in range(8):
		var force: Vector3 = nozzle_visual_force(i) if i<4 else roll_jet_forces[i-4]
		if force.length()<100.0: continue
		var mount: Vector3 = Vector3(MOUNTS[i].x,-0.05,MOUNTS[i].z) if i<4 else ROLL_MOUNTS[i-4]
		var exhaust := -force.normalized()
		cast.from = global_transform*mount
		cast.to = cast.from+exhaust*7.0
		if absf(exhaust.y)<0.25: cast.to += Vector3.DOWN*0.6
		var hit := get_world_3d().direct_space_state.intersect_ray(cast)
		if hit.is_empty(): continue
		var proximity := pow(clampf(1.0-cast.from.distance_to(hit.position)/7.0,0.0,1.0),1.4)
		var strength: float = force.length()/LIFT*proximity
		downwash_strength += strength
		wash_position += hit.position*strength
		wash_normal += hit.normal*strength
	if downwash_strength>0.01:
		var normal := wash_normal.normalized()
		dust.global_transform = Transform3D(Basis(Quaternion(Vector3.UP,normal)),wash_position/downwash_strength+normal*0.18)
	dust.emitting = downwash_strength>0.025
	dust.amount_ratio = clampf(downwash_strength,0.0,1.0)
	if pending_impact:
		if dust_cooldown==0.0 and not ground.is_empty():
			var strength := clampf(impact_speed/12.0,0.25,1.0)
			landing_dust.global_transform = Transform3D(Basis(Quaternion(Vector3.UP,ground.normal)),ground.position+ground.normal*0.18)
			landing_dust.amount_ratio = strength
			var smoke := landing_dust.process_material as ParticleProcessMaterial
			smoke.radial_velocity_min = 2.0+strength*1.5
			smoke.radial_velocity_max = 4.0+strength*4.0
			landing_dust.restart()
			dust_cooldown = 0.8
		impact_audio.volume_db = clampf(-24.0+impact_speed*1.4,-24.0,-5.0)+audio_view_gain
		impact_audio.play()
		pending_impact = false
	impact_speed = move_toward(impact_speed,0.0,delta*18.0)
	var any_jet := jet_nodes.any(func(j):return j.emitting) or roll_jet_nodes.any(func(j):return j.emitting)
	audio_view_gain = move_toward(audio_view_gain,1.5 if cockpit_audio else 0.0,delta*6.0)
	var desired_db := -12.0+audio_view_gain if any_jet else -60.0
	jet_audio.volume_db = lerpf(jet_audio.volume_db,desired_db,1.0-exp(-delta*7.0))
	var speed := linear_velocity.length()
	var grounded := wheel_contacts>0
	var blend := 1.0-exp(-delta*9.0)
	var motor_db := clampf(-32.0+speed*0.35+float(controls.throttle)*8.0,-32.0,-13.0) if grounded and speed>0.5 else -60.0
	motor_audio.volume_db = lerpf(motor_audio.volume_db,motor_db+audio_view_gain,blend)
	motor_audio.pitch_scale = lerpf(motor_audio.pitch_scale,0.7+minf(speed,60.0)*0.035,blend)
	var road_db := clampf(-36.0+speed*0.5,-36.0,-15.0) if speed>1.0 else -60.0
	if not grounded: road_db -= 9.0
	road_audio.volume_db = lerpf(road_audio.volume_db,road_db+audio_view_gain,blend)
	road_audio.pitch_scale = 0.7+minf(speed,60.0)*0.018
	var slip := clampf((tire_slip-0.8)/6.0,0.0,1.0) if grounded and speed>4.0 else 0.0
	skid_audio.volume_db = lerpf(skid_audio.volume_db,lerpf(-42.0,-12.0,slip)+audio_view_gain if slip>0.01 else -60.0,blend)
	skid_audio.pitch_scale = 0.9+slip*0.25
	for i in range(tire_smoke.size()):
		tire_smoke[i].position = MOUNTS[i+2]+Vector3.DOWN*(float(wheel_lengths[i+2])+RADIUS-0.06)
		tire_smoke[i].emitting = slip>0.1
		tire_smoke[i].amount_ratio = maxf(0.05,slip*0.8)
	if audio_muted:
		for player in [motor_audio,road_audio,skid_audio,jet_audio,impact_audio]:
			player.volume_db = -80.0

func _particle(amount: int, lifetime: float, size: float, color: Color) -> GPUParticles3D:
	var node := GPUParticles3D.new()
	node.amount = amount
	node.lifetime = lifetime
	node.emitting = false
	node.visibility_aabb = AABB(Vector3(-30,-30,-30),Vector3(60,60,60))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 8.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = 10.0
	process.initial_velocity_max = 18.0
	process.scale_min = size*0.5
	process.scale_max = size
	var grad := Gradient.new()
	grad.set_color(0,color)
	grad.set_color(1,Color(color.r,color.g,color.b,0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	process.color_ramp = ramp
	node.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.no_depth_test = false
	quad.material = material
	node.draw_pass_1 = quad
	return node

func _make_cockpit_mirror() -> void:
	cockpit_mirror = Node3D.new()
	cockpit_mirror.name = "CockpitMirror"
	add_child(cockpit_mirror)
	cockpit_mirror.position = Vector3(0,0.80,-0.56)
	var frame := Art.box(cockpit_mirror,Vector3(0.44,0.14,0.035),Vector3.ZERO,Art.mat(Color("0b1017"),0.45,0.22))
	frame.layers = 4
	var stem := Art.box(cockpit_mirror,Vector3(0.022,0.075,0.02),Vector3(0,0.09,0),Art.mat(Color("18212a")))
	stem.layers = 4
	mirror_view = SubViewport.new()
	mirror_view.size = Vector2i(512,160)
	mirror_view.world_3d = get_world_3d()
	mirror_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(mirror_view)
	mirror_camera = Camera3D.new()
	mirror_camera.fov = 24
	mirror_camera.near = 0.03
	mirror_camera.cull_mask = 3
	mirror_view.add_child(mirror_camera)
	var surface := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.405,0.108)
	surface.mesh = quad
	surface.position.z = 0.02
	surface.layers = 4
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D reflection : source_color;
void fragment() { ALBEDO = texture(reflection, vec2(1.0-UV.x, UV.y)).rgb; }
"""
	var reflection := ShaderMaterial.new()
	reflection.shader = shader
	reflection.set_shader_parameter("reflection",mirror_view.get_texture())
	surface.material_override = reflection
	cockpit_mirror.add_child(surface)
	cockpit_mirror.hide()

func _make_effects() -> void:
	# A radial texture keeps exhaust clouds soft rather than square billboards.
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var radius := Vector2(x-31.5,y-31.5).length()/31.5
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0.0,1.0-radius),2.0)))
	var texture := ImageTexture.create_from_image(image)
	for p in MOUNTS:
		var jet := _particle(96,0.18,0.35,Color(0.5,0.82,1.0,0.22))
		jet.fixed_fps = 120
		add_child(jet)
		jet.position = Vector3(p.x,-0.05,p.z)
		(jet.draw_pass_1.material as StandardMaterial3D).albedo_texture = texture
		jet_nodes.append(jet)
	var gas_shader := Shader.new()
	gas_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
varying float along;
void vertex() { along = VERTEX.y + 0.5; }
void fragment() {
 ALBEDO = vec3(0.75, 0.91, 1.0);
 ALPHA = 0.50 * pow(max(0.0, 1.0-along), 1.5) * (0.94+0.06*sin(TIME*38.0));
}
"""
	var gas_material := ShaderMaterial.new()
	gas_material.shader = gas_shader
	for jet in jet_nodes:
		var cone := CylinderMesh.new()
		cone.height = 1.0
		cone.top_radius = 0.13
		cone.bottom_radius = 0.035
		cone.radial_segments = 20
		cone.cap_top = false
		cone.cap_bottom = false
		var core := MeshInstance3D.new()
		core.mesh = cone
		core.material_override = gas_material
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.visible = false
		jet.add_child(core)
		jet_cores.append(core)
	for p in ROLL_MOUNTS:
		var nozzle := Art.box(self,Vector3(0.028,0.045,0.12),p,Art.mat(Color("18222a"),0.8,0.3))
		nozzle.name = "RollNozzle"
		var jet := _particle(72,0.18,0.4,Color(0.5,0.82,1.0,0.3))
		jet.fixed_fps = 120
		add_child(jet)
		jet.position = p
		(jet.draw_pass_1.material as StandardMaterial3D).albedo_texture = texture
		var process := jet.process_material as ParticleProcessMaterial
		process.initial_velocity_min = 16.0
		process.initial_velocity_max = 24.0
		process.spread = 9.0
		roll_jet_nodes.append(jet)
		var cone := CylinderMesh.new()
		cone.height = 1.0
		cone.top_radius = 0.15
		cone.bottom_radius = 0.035
		cone.radial_segments = 16
		var core := MeshInstance3D.new()
		core.mesh = cone
		core.material_override = gas_material
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.visible = false
		jet.add_child(core)
		roll_jet_cores.append(core)
	# Irregular translucent lobes overlap into a continuous, expanding cloud.
	var noise := FastNoiseLite.new()
	noise.seed = 27
	noise.frequency = 0.055
	noise.fractal_octaves = 4
	var smoke_image := Image.create(128,128,false,Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var radius := Vector2(x-63.5,y-63.5).length()/63.5
			var cloud := noise.get_noise_2d(x,y)*0.5+0.5
			var alpha := smoothstep(1.0,0.25,radius+cloud*0.24)*lerpf(0.25,1.0,cloud)
			smoke_image.set_pixel(x,y,Color(0.65+cloud*0.35,0.68+cloud*0.32,0.72+cloud*0.28,alpha))
	var smoke_texture := ImageTexture.create_from_image(smoke_image)
	dust = _particle(1900,1.8,6.0,Color(0.86,0.90,0.94,0.42))
	dust.fixed_fps = 60
	add_child(dust)
	dust.top_level = true
	landing_dust = _particle(480,2.6,3.1,Color(0.69,0.74,0.78,0.24))
	add_child(landing_dust)
	landing_dust.top_level = true
	landing_dust.one_shot = true
	landing_dust.explosiveness = 0.92
	for emitter in [dust,landing_dust]:
		emitter.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		var dm := emitter.process_material as ParticleProcessMaterial
		dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		dm.emission_ring_axis = Vector3.UP
		dm.emission_ring_radius = 1.4
		dm.emission_ring_inner_radius = 0.7
		dm.emission_ring_height = 0.15
		dm.direction = Vector3.UP
		dm.spread = 25.0
		dm.initial_velocity_min = 0.3
		dm.initial_velocity_max = 1.0
		dm.radial_velocity_min = 3.5
		dm.radial_velocity_max = 7.0
		dm.gravity = Vector3(0,0.18,0)
		dm.damping_min = 0.7
		dm.damping_max = 1.4
		dm.angle_min = -180.0
		dm.angle_max = 180.0
		dm.angular_velocity_min = -18.0
		dm.angular_velocity_max = 18.0
		var growth := Curve.new()
		growth.add_point(Vector2(0,0.45))
		growth.add_point(Vector2(0.35,1.0))
		growth.add_point(Vector2(1,1.6))
		var scale_texture := CurveTexture.new()
		scale_texture.curve = growth
		dm.scale_curve = scale_texture
		var color := Color(0.69,0.74,0.78)
		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0,0.08,0.35,1])
		fade.colors = PackedColorArray([Color(color,0),Color(color,0.24),Color(color,0.16),Color(color,0)])
		(dm.color_ramp as GradientTexture1D).gradient = fade
		(emitter.draw_pass_1.material as StandardMaterial3D).albedo_texture = smoke_texture
	var wash := dust.process_material as ParticleProcessMaterial
	wash.scale_min = 3.8
	wash.scale_max = 6.0
	wash.initial_velocity_min = 1.0
	wash.initial_velocity_max = 2.4
	wash.radial_velocity_min = 4.0
	wash.radial_velocity_max = 9.0
	wash.emission_ring_radius = 2.0
	wash.emission_ring_inner_radius = 1.0
	wash.color_ramp = wash.color_ramp.duplicate(true)
	var wash_growth := Curve.new()
	wash_growth.add_point(Vector2(0,0.65))
	wash_growth.add_point(Vector2(0.35,1.0))
	wash_growth.add_point(Vector2(1,1.5))
	var wash_scale := CurveTexture.new()
	wash_scale.curve = wash_growth
	wash.scale_curve = wash_scale
	var wash_fade := (wash.color_ramp as GradientTexture1D).gradient
	wash_fade.colors = PackedColorArray([Color(0.86,0.90,0.94,0),Color(0.86,0.90,0.94,0.42),Color(0.86,0.90,0.94,0.32),Color(0.86,0.90,0.94,0)])
	for i in range(2):
		var smoke := _particle(400,1.4,2.2,Color(0.69,0.74,0.78,0.18))
		smoke.fixed_fps = 120
		add_child(smoke)
		var dm := (dust.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		dm.scale_min = 1.1
		dm.scale_max = 2.3
		dm.color_ramp = dm.color_ramp.duplicate(true)
		var fade := (dm.color_ramp as GradientTexture1D).gradient
		for point in range(fade.get_point_count()):
			var color := fade.get_color(point)
			color.a *= 0.65
			fade.set_color(point,color)
		dm.radial_velocity_min = 0.3
		dm.radial_velocity_max = 1.0
		smoke.process_material = dm
		(smoke.draw_pass_1.material as StandardMaterial3D).albedo_texture = smoke_texture
		tire_smoke.append(smoke)
	for file in ["motor","road","skid"]:
		var player := AudioStreamPlayer3D.new()
		player.stream = load("res://audio/"+file+".wav")
		player.volume_db = -60.0
		add_child(player)
		player.play()
		if file=="motor": motor_audio = player
		elif file=="road": road_audio = player
		else: skid_audio = player
	jet_audio = AudioStreamPlayer3D.new()
	jet_audio.stream = load("res://audio/jet.wav")
	jet_audio.volume_db = -60
	add_child(jet_audio)
	jet_audio.play()
	impact_audio = AudioStreamPlayer3D.new()
	impact_audio.stream = load("res://audio/land.wav")
	add_child(impact_audio)
	for player in [motor_audio,road_audio,skid_audio,jet_audio,impact_audio]:
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		player.max_distance = 0.0
		player.attenuation_filter_cutoff_hz = 20500
		player.panning_strength = 0.0
