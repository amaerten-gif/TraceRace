extends Node2D

var in_menu: bool = true
var play_button: Rect2 = Rect2(170.0, 1110.0, 740.0, 150.0)
var car_texture: Texture2D

const SAVE_PATH: String = "user://trace_race_engine.cfg"
const DRAW_MIN_DISTANCE: float = 7.0
const MAX_RAW_POINTS: int = 900
const PATH_RESAMPLE_DISTANCE: float = 14.0
const START_RADIUS: float = 90.0

const TRACKS: Array[Dictionary] = [
    {"name": "FJORD OVAL", "center": Vector2(540.0, 900.0), "outer_x": 445.0, "outer_y": 650.0, "inner_x": 255.0, "inner_y": 420.0, "start": Vector2(540.0, 1435.0), "gravel": Rect2(755.0, 730.0, 150.0, 250.0)},
    {"name": "HARBOUR RING", "center": Vector2(540.0, 900.0), "outer_x": 430.0, "outer_y": 570.0, "inner_x": 225.0, "inner_y": 350.0, "start": Vector2(540.0, 1370.0), "gravel": Rect2(175.0, 720.0, 170.0, 220.0)},
    {"name": "CLIFF LOOP", "center": Vector2(540.0, 900.0), "outer_x": 465.0, "outer_y": 625.0, "inner_x": 300.0, "inner_y": 390.0, "start": Vector2(540.0, 1415.0), "gravel": Rect2(760.0, 1010.0, 145.0, 210.0)}
]

var current_track_index: int = 0
var road_width_scale: float = 1.0
var start_position: Vector2 = Vector2(540.0, 1435.0)

var raw_points: PackedVector2Array = PackedVector2Array()
var driving_path: PackedVector2Array = PackedVector2Array()
var speed_hints: PackedFloat32Array = PackedFloat32Array()
var ghost_samples: PackedVector2Array = PackedVector2Array()
var best_ghost_samples: PackedVector2Array = PackedVector2Array()

var drawing: bool = false
var racing: bool = false
var race_finished: bool = false
var telemetry_enabled: bool = false
var show_raw_path: bool = false
var ghost_enabled: bool = true

var path_index: int = 0
var car_position: Vector2 = Vector2(540.0, 1435.0)
var car_rotation: float = -PI / 2.0
var car_velocity: Vector2 = Vector2.ZERO
var race_time: float = 0.0
var best_time: float = 0.0
var offroad_time: float = 0.0
var ghost_record_accumulator: float = 0.0
var message: String = "DRAW YOUR RACING LINE"
var current_surface: String = "ASPHALT"
var tyre_load: float = 0.0
var slip_angle: float = 0.0
var steering_error: float = 0.0
var body_roll: float = 0.0
var longitudinal_g: float = 0.0
var previous_speed: float = 0.0
var countdown_active: bool = false
var countdown_time: float = 0.0
var countdown_value: int = 3
var go_flash_time: float = 0.0
var skid_marks: PackedVector2Array = PackedVector2Array()
var skid_accumulator: float = 0.0

var undo_button: Rect2 = Rect2(50.0, 1665.0, 190.0, 105.0)
var clear_button: Rect2 = Rect2(260.0, 1665.0, 190.0, 105.0)
var race_button: Rect2 = Rect2(790.0, 1665.0, 240.0, 105.0)
var telemetry_button: Rect2 = Rect2(50.0, 1795.0, 285.0, 80.0)
var raw_button: Rect2 = Rect2(365.0, 1795.0, 285.0, 80.0)
var ghost_button: Rect2 = Rect2(680.0, 1795.0, 350.0, 80.0)
var track_button: Rect2 = Rect2(390.0, 205.0, 300.0, 70.0)
var narrow_button: Rect2 = Rect2(710.0, 205.0, 145.0, 70.0)
var wide_button: Rect2 = Rect2(875.0, 205.0, 145.0, 70.0)

func _ready() -> void:
    car_texture = load("res://assets/car_blue.png") as Texture2D
    _apply_track()
    _load_best()
    queue_redraw()

func _process(delta: float) -> void:
    if in_menu:
        return
    if countdown_active:
        countdown_time -= delta
        var new_value: int = maxi(1, int(ceil(countdown_time)))
        if new_value != countdown_value:
            countdown_value = new_value
        if countdown_time <= 0.0:
            countdown_active = false
            racing = true
            go_flash_time = 0.65
            message = "GO!"
        queue_redraw()
        return
    if go_flash_time > 0.0:
        go_flash_time = maxf(0.0, go_flash_time - delta)
    if racing:
        race_time += delta
        _advance_car(delta)
        _record_ghost(delta)
        queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
    if in_menu:
        var menu_position: Vector2 = Vector2.ZERO
        var menu_pressed: bool = false
        if event is InputEventScreenTouch:
            var menu_touch: InputEventScreenTouch = event as InputEventScreenTouch
            menu_position = menu_touch.position
            menu_pressed = menu_touch.pressed
        elif event is InputEventMouseButton:
            var menu_mouse: InputEventMouseButton = event as InputEventMouseButton
            if menu_mouse.button_index == MOUSE_BUTTON_LEFT:
                menu_position = menu_mouse.position
                menu_pressed = menu_mouse.pressed
        if menu_pressed and play_button.has_point(menu_position):
            in_menu = false
            message = "DRAW YOUR RACING LINE"
            queue_redraw()
        return
    if event is InputEventScreenTouch:
        var touch: InputEventScreenTouch = event
        if touch.pressed:
            _handle_press(touch.position)
        else:
            _finish_drawing()
    elif event is InputEventScreenDrag:
        var drag: InputEventScreenDrag = event
        if drawing and not racing and not countdown_active:
            _append_raw_point(drag.position)
    elif event is InputEventMouseButton:
        var mouse_button: InputEventMouseButton = event
        if mouse_button.button_index == MOUSE_BUTTON_LEFT:
            if mouse_button.pressed:
                _handle_press(mouse_button.position)
            else:
                _finish_drawing()
    elif event is InputEventMouseMotion:
        var motion: InputEventMouseMotion = event
        if drawing and not racing and not countdown_active:
            _append_raw_point(motion.position)

func _handle_press(position: Vector2) -> void:
    if track_button.has_point(position) and not racing and not countdown_active:
        current_track_index = (current_track_index + 1) % TRACKS.size()
        _apply_track()
        _clear_run()
        message = "Track changed — draw a new lap"
        return
    if narrow_button.has_point(position) and not racing and not countdown_active:
        road_width_scale = clampf(road_width_scale - 0.08, 0.76, 1.24)
        _clear_run()
        message = "Road width %.0f%%" % (road_width_scale * 100.0)
        return
    if wide_button.has_point(position) and not racing and not countdown_active:
        road_width_scale = clampf(road_width_scale + 0.08, 0.76, 1.24)
        _clear_run()
        message = "Road width %.0f%%" % (road_width_scale * 100.0)
        return
    if undo_button.has_point(position):
        _undo_path_section()
        return
    if clear_button.has_point(position):
        _clear_run()
        return
    if race_button.has_point(position):
        _start_race()
        return
    if telemetry_button.has_point(position):
        telemetry_enabled = not telemetry_enabled
        queue_redraw()
        return
    if raw_button.has_point(position):
        show_raw_path = not show_raw_path
        queue_redraw()
        return
    if ghost_button.has_point(position):
        ghost_enabled = not ghost_enabled
        queue_redraw()
        return
    if position.y < 1580.0 and not racing and not countdown_active:
        raw_points.clear()
        driving_path.clear()
        speed_hints.clear()
        raw_points.append(position)
        drawing = true
        race_finished = false
        message = "Draw clockwise and return to the start gate"
        queue_redraw()

func _append_raw_point(position: Vector2) -> void:
    if position.y >= 1580.0 or raw_points.size() >= MAX_RAW_POINTS:
        return
    if raw_points.is_empty() or raw_points[raw_points.size() - 1].distance_to(position) >= DRAW_MIN_DISTANCE:
        raw_points.append(position)
        driving_path = _build_driving_path(raw_points)
        speed_hints = _build_speed_hints(driving_path)
        queue_redraw()

func _finish_drawing() -> void:
    if not drawing:
        return
    drawing = false
    driving_path = _build_driving_path(raw_points)
    speed_hints = _build_speed_hints(driving_path)
    var validation: String = _validate_path()
    if validation.is_empty():
        message = "READY — TAP RACE"
    else:
        message = validation
    queue_redraw()

func _build_driving_path(source: PackedVector2Array) -> PackedVector2Array:
    if source.size() < 3:
        return source.duplicate()
    var reduced: PackedVector2Array = _reduce_points(source, 7.0)
    var smoothed: PackedVector2Array = _chaikin(reduced, 2)
    return _resample_path(smoothed, PATH_RESAMPLE_DISTANCE)

func _reduce_points(source: PackedVector2Array, minimum_distance: float) -> PackedVector2Array:
    var result: PackedVector2Array = PackedVector2Array()
    if source.is_empty():
        return result
    result.append(source[0])
    for i in range(1, source.size() - 1):
        if result[result.size() - 1].distance_to(source[i]) >= minimum_distance:
            result.append(source[i])
    if source.size() > 1:
        result.append(source[source.size() - 1])
    return result

func _chaikin(source: PackedVector2Array, iterations: int) -> PackedVector2Array:
    var working: PackedVector2Array = source.duplicate()
    for iteration in range(iterations):
        if working.size() < 3:
            break
        var next_points: PackedVector2Array = PackedVector2Array()
        next_points.append(working[0])
        for i in range(working.size() - 1):
            var a: Vector2 = working[i]
            var b: Vector2 = working[i + 1]
            next_points.append(a.lerp(b, 0.25))
            next_points.append(a.lerp(b, 0.75))
        next_points.append(working[working.size() - 1])
        working = next_points
    return working

func _resample_path(source: PackedVector2Array, spacing: float) -> PackedVector2Array:
    var result: PackedVector2Array = PackedVector2Array()
    if source.size() < 2:
        return source.duplicate()
    result.append(source[0])
    var carry: float = 0.0
    var previous: Vector2 = source[0]
    for i in range(1, source.size()):
        var target: Vector2 = source[i]
        var segment: Vector2 = target - previous
        var segment_length: float = segment.length()
        if segment_length <= 0.001:
            continue
        var direction: Vector2 = segment / segment_length
        var travelled: float = spacing - carry
        while travelled <= segment_length:
            result.append(previous + direction * travelled)
            travelled += spacing
        carry = segment_length - (travelled - spacing)
        previous = target
    if result[result.size() - 1].distance_to(source[source.size() - 1]) > 2.0:
        result.append(source[source.size() - 1])
    return result

func _build_speed_hints(path: PackedVector2Array) -> PackedFloat32Array:
    var result: PackedFloat32Array = PackedFloat32Array()
    if path.is_empty():
        return result
    for i in range(path.size()):
        var before_index: int = maxi(0, i - 4)
        var after_index: int = mini(path.size() - 1, i + 4)
        var incoming: Vector2 = (path[i] - path[before_index]).normalized()
        var outgoing: Vector2 = (path[after_index] - path[i]).normalized()
        var turn_amount: float = absf(incoming.angle_to(outgoing))
        var hint: float = clampf(1.0 - turn_amount / 1.20, 0.32, 1.0)
        result.append(hint)
    return result

func _undo_path_section() -> void:
    if racing or raw_points.is_empty():
        return
    var remove_count: int = mini(18, raw_points.size())
    for i in range(remove_count):
        raw_points.remove_at(raw_points.size() - 1)
    driving_path = _build_driving_path(raw_points)
    speed_hints = _build_speed_hints(driving_path)
    message = "Last section removed"
    queue_redraw()

func _clear_run() -> void:
    raw_points.clear()
    driving_path.clear()
    speed_hints.clear()
    ghost_samples.clear()
    drawing = false
    racing = false
    race_finished = false
    countdown_active = false
    countdown_time = 0.0
    go_flash_time = 0.0
    race_time = 0.0
    offroad_time = 0.0
    path_index = 0
    car_position = start_position
    car_rotation = -PI / 2.0
    car_velocity = Vector2.ZERO
    current_surface = "ASPHALT"
    tyre_load = 0.0
    slip_angle = 0.0
    steering_error = 0.0
    body_roll = 0.0
    longitudinal_g = 0.0
    previous_speed = 0.0
    skid_marks.clear()
    skid_accumulator = 0.0
    message = "DRAW YOUR RACING LINE"
    queue_redraw()

func _validate_path() -> String:
    if driving_path.size() < 90:
        return "Draw a longer route around the complete circuit"
    if driving_path[0].distance_to(start_position) > START_RADIUS:
        return "Start inside the white gate"
    if driving_path[driving_path.size() - 1].distance_to(start_position) > START_RADIUS:
        return "Finish back inside the white gate"
    var outside_count: int = 0
    for point in driving_path:
        if _surface_at(point) == "WATER":
            outside_count += 1
    if float(outside_count) / float(driving_path.size()) > 0.18:
        return "Too much of the route is outside the playable area"
    return ""

func _start_race() -> void:
    if racing or countdown_active:
        return
    var validation: String = _validate_path()
    if not validation.is_empty():
        message = validation
        queue_redraw()
        return
    racing = false
    countdown_active = true
    countdown_time = 3.0
    countdown_value = 3
    race_finished = false
    go_flash_time = 0.0
    race_time = 0.0
    offroad_time = 0.0
    ghost_record_accumulator = 0.0
    ghost_samples.clear()
    path_index = 0
    car_position = driving_path[0]
    var initial_direction: Vector2 = (driving_path[1] - driving_path[0]).normalized()
    car_velocity = initial_direction * 90.0
    car_rotation = initial_direction.angle()
    previous_speed = car_velocity.length()
    skid_marks.clear()
    skid_accumulator = 0.0
    message = "GET READY"
    queue_redraw()

func _advance_car(delta: float) -> void:
    if path_index >= driving_path.size() - 1:
        _finish_race()
        return
    while path_index < driving_path.size() - 2 and car_position.distance_to(driving_path[path_index + 1]) < 45.0:
        path_index += 1

    var target_index: int = mini(path_index + 5, driving_path.size() - 1)
    var target: Vector2 = driving_path[target_index]
    var desired_direction: Vector2 = (target - car_position).normalized()
    current_surface = _surface_at(car_position)

    var hint: float = speed_hints[mini(path_index, speed_hints.size() - 1)]
    var surface_speed: float = _surface_speed_multiplier(current_surface)
    var surface_grip: float = _surface_grip_multiplier(current_surface)
    var desired_speed: float = 585.0 * hint * surface_speed
    var current_speed: float = car_velocity.length()

    var acceleration: float = 520.0 * surface_grip
    var braking: float = 860.0 * (0.75 + surface_grip * 0.25)
    var change_rate: float = acceleration if current_speed <= desired_speed else braking
    var next_speed: float = move_toward(current_speed, desired_speed, change_rate * delta)
    longitudinal_g = (next_speed - previous_speed) / maxf(delta, 0.001) / 980.0
    previous_speed = next_speed

    var velocity_direction: Vector2 = desired_direction
    if car_velocity.length() > 2.0:
        velocity_direction = car_velocity.normalized()

    steering_error = velocity_direction.angle_to(desired_direction)
    slip_angle = absf(steering_error)
    var speed_load: float = clampf(next_speed / 585.0, 0.0, 1.35)
    tyre_load = clampf((slip_angle / 0.62) * speed_load / maxf(surface_grip, 0.20), 0.0, 1.6)

    var peak_grip: float = 1.0
    var sliding_grip: float = 0.34
    var grip_factor: float = peak_grip
    if tyre_load > 0.72:
        var slide_blend: float = clampf((tyre_load - 0.72) / 0.70, 0.0, 1.0)
        grip_factor = lerpf(peak_grip, sliding_grip, slide_blend)

    var base_turn: float = 5.15 * surface_grip
    var speed_turn_penalty: float = clampf(340.0 / maxf(next_speed, 115.0), 0.30, 1.35)
    var turn_blend: float = clampf(base_turn * speed_turn_penalty * grip_factor * delta, 0.0, 1.0)
    var corrected_direction: Vector2 = velocity_direction.slerp(desired_direction, turn_blend).normalized()

    # Mild momentum drift when the tyre is overloaded. This produces natural understeer
    # without making the car unpredictable or requiring real-time steering.
    if tyre_load > 0.85:
        var drift_amount: float = clampf((tyre_load - 0.85) * 0.16, 0.0, 0.10)
        corrected_direction = corrected_direction.slerp(velocity_direction, drift_amount).normalized()
        next_speed *= 1.0 - clampf((tyre_load - 0.85) * 0.018, 0.0, 0.035)

    car_velocity = corrected_direction * next_speed
    car_position += car_velocity * delta
    car_rotation = corrected_direction.angle()
    body_roll = lerpf(body_roll, clampf(-steering_error * speed_load * 0.75, -0.30, 0.30), clampf(delta * 7.0, 0.0, 1.0))

    skid_accumulator += delta
    if tyre_load > 0.92 and next_speed > 185.0 and skid_accumulator >= 0.045:
        skid_accumulator = 0.0
        skid_marks.append(car_position)
        if skid_marks.size() > 220:
            skid_marks.remove_at(0)

    if current_surface != "ASPHALT" and current_surface != "KERB":
        offroad_time += delta
    if path_index >= driving_path.size() - 5 and car_position.distance_to(driving_path[driving_path.size() - 1]) < 50.0:
        _finish_race()

func _record_ghost(delta: float) -> void:
    ghost_record_accumulator += delta
    if ghost_record_accumulator >= 0.05:
        ghost_record_accumulator = 0.0
        ghost_samples.append(car_position)

func _finish_race() -> void:
    racing = false
    race_finished = true
    race_time += offroad_time * 1.25
    if best_time <= 0.0 or race_time < best_time:
        best_time = race_time
        best_ghost_samples = ghost_samples.duplicate()
        _save_best()
        message = "NEW BEST  %.2fs" % race_time
    else:
        message = "FINISHED  %.2fs" % race_time
    queue_redraw()

func _track_data() -> Dictionary:
    return TRACKS[current_track_index]

func _apply_track() -> void:
    var data: Dictionary = _track_data()
    start_position = data["start"]
    car_position = start_position

func _surface_at(point: Vector2) -> String:
    var data: Dictionary = _track_data()
    var center: Vector2 = data["center"]
    var local: Vector2 = point - center
    var outer_x: float = float(data["outer_x"])
    var outer_y: float = float(data["outer_y"])
    var inner_x: float = float(data["inner_x"])
    var inner_y: float = float(data["inner_y"])
    var mid_x: float = (outer_x + inner_x) * 0.5
    var mid_y: float = (outer_y + inner_y) * 0.5
    var half_x: float = (outer_x - inner_x) * 0.5 * road_width_scale
    var half_y: float = (outer_y - inner_y) * 0.5 * road_width_scale
    var adjusted_outer_x: float = mid_x + half_x
    var adjusted_outer_y: float = mid_y + half_y
    var adjusted_inner_x: float = maxf(40.0, mid_x - half_x)
    var adjusted_inner_y: float = maxf(40.0, mid_y - half_y)
    var outer_value: float = pow(local.x / adjusted_outer_x, 2.0) + pow(local.y / adjusted_outer_y, 2.0)
    var inner_value: float = pow(local.x / adjusted_inner_x, 2.0) + pow(local.y / adjusted_inner_y, 2.0)
    if outer_value > 1.10 or inner_value < 0.78:
        return "WATER"
    if outer_value > 1.0 or inner_value < 1.0:
        return "GRASS"
    if outer_value > 0.94 or inner_value < 1.08:
        return "KERB"
    var gravel_zone: Rect2 = data["gravel"]
    if gravel_zone.has_point(point):
        return "GRAVEL"
    return "ASPHALT"

func _surface_speed_multiplier(surface: String) -> float:
    if surface == "KERB":
        return 0.92
    if surface == "GRAVEL":
        return 0.72
    if surface == "GRASS":
        return 0.52
    if surface == "WATER":
        return 0.30
    return 1.0

func _surface_grip_multiplier(surface: String) -> float:
    if surface == "KERB":
        return 0.90
    if surface == "GRAVEL":
        return 0.68
    if surface == "GRASS":
        return 0.48
    if surface == "WATER":
        return 0.25
    return 1.0

func _save_best() -> void:
    var config: ConfigFile = ConfigFile.new()
    config.set_value("engine", "best_time", best_time)
    var serialised: Array = []
    for point in best_ghost_samples:
        serialised.append([point.x, point.y])
    config.set_value("engine", "best_ghost", serialised)
    config.save(SAVE_PATH)

func _load_best() -> void:
    var config: ConfigFile = ConfigFile.new()
    if config.load(SAVE_PATH) != OK:
        return
    best_time = float(config.get_value("engine", "best_time", 0.0))
    var serialised: Array = config.get_value("engine", "best_ghost", [])
    for item in serialised:
        if item is Array and item.size() >= 2:
            best_ghost_samples.append(Vector2(float(item[0]), float(item[1])))

func _draw() -> void:
    if in_menu:
        _draw_production_menu()
        return
    _draw_world()
    _draw_track()
    _draw_paths()
    _draw_skid_marks()
    _draw_ghost()
    _draw_car()
    _draw_countdown_overlay()
    _draw_ui()

func _draw_production_menu() -> void:
    draw_rect(Rect2(0.0, 0.0, 1080.0, 1920.0), Color("071116"))
    draw_rect(Rect2(0.0, 0.0, 1080.0, 650.0), Color("0b3342"))
    draw_circle(Vector2(850.0, 180.0), 230.0, Color("194f56"))
    draw_circle(Vector2(230.0, 360.0), 300.0, Color("153f46"))
    draw_string(ThemeDB.fallback_font, Vector2(0.0, 700.0), "FJORD GAMES", HORIZONTAL_ALIGNMENT_CENTER, 1080.0, 28, Color("c9d7da"))
    draw_string(ThemeDB.fallback_font, Vector2(0.0, 870.0), "TRACE RACE", HORIZONTAL_ALIGNMENT_CENTER, 1080.0, 76, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(0.0, 930.0), "EVERY LINE MATTERS", HORIZONTAL_ALIGNMENT_CENTER, 1080.0, 24, Color("f08a18"))
    draw_rect(play_button, Color("d66c08"))
    draw_string(ThemeDB.fallback_font, Vector2(play_button.position.x, play_button.position.y + 96.0), "PLAY", HORIZONTAL_ALIGNMENT_CENTER, play_button.size.x, 38, Color("ffffff"))
    draw_rect(Rect2(170.0, 1300.0, 740.0, 115.0), Color("14252c"))
    draw_string(ThemeDB.fallback_font, Vector2(170.0, 1375.0), "GARAGE - COMING NEXT", HORIZONTAL_ALIGNMENT_CENTER, 740.0, 24, Color("a8bbc0"))
    draw_string(ThemeDB.fallback_font, Vector2(0.0, 1810.0), "TRACE RACE HD - GRAPHICS PASS 1", HORIZONTAL_ALIGNMENT_CENTER, 1080.0, 18, Color("7f969c"))

func _draw_world() -> void:
    # Deep fjord water base with subtle depth bands.
    draw_rect(Rect2(0.0, 0.0, 1080.0, 1920.0), Color("0b2b38"))
    draw_rect(Rect2(0.0, 180.0, 1080.0, 1400.0), Color("0f3d4c"))
    for i in range(16):
        var y: float = 250.0 + float(i) * 82.0
        var alpha: float = 0.035 + float(i % 3) * 0.012
        draw_line(Vector2(0.0, y), Vector2(1080.0, y - 34.0), Color(0.45, 0.78, 0.84, alpha), 3.0, true)

    # Mountain shelves / islands around the circuit.
    _draw_mountain_mass(Vector2(115.0, 455.0), 245.0, 180.0)
    _draw_mountain_mass(Vector2(980.0, 515.0), 300.0, 225.0)
    _draw_mountain_mass(Vector2(125.0, 1280.0), 310.0, 235.0)
    _draw_mountain_mass(Vector2(955.0, 1270.0), 270.0, 210.0)

    # Trackside details are deterministic so screenshots remain consistent.
    var tree_positions: Array[Vector2] = [
        Vector2(95, 610), Vector2(150, 675), Vector2(905, 650), Vector2(955, 720),
        Vector2(120, 1060), Vector2(185, 1130), Vector2(875, 1080), Vector2(945, 1160),
        Vector2(240, 420), Vector2(820, 410), Vector2(250, 1390), Vector2(825, 1410)
    ]
    for pos in tree_positions:
        _draw_pine_tree(pos, 1.0)

    _draw_cabin(Vector2(120.0, 820.0), -0.10)
    _draw_cabin(Vector2(925.0, 935.0), 0.12)
    _draw_boat(Vector2(112.0, 500.0), 0.15)
    _draw_boat(Vector2(955.0, 1320.0), -0.30)

    # Soft water highlights.
    for i in range(24):
        var x: float = 35.0 + float((i * 173) % 1010)
        var y: float = 300.0 + float((i * 239) % 1180)
        draw_line(Vector2(x, y), Vector2(x + 34.0, y - 5.0), Color(0.70, 0.90, 0.93, 0.13), 3.0, true)

func _draw_mountain_mass(center: Vector2, radius_x: float, radius_y: float) -> void:
    _draw_trace_ellipse(center + Vector2(7.0, 10.0), radius_x, radius_y, Color(0.01, 0.02, 0.02, 0.28))
    _draw_trace_ellipse(center, radius_x, radius_y, Color("214d46"))
    _draw_trace_ellipse(center + Vector2(-18.0, -18.0), radius_x * 0.78, radius_y * 0.72, Color("38695b"))
    _draw_trace_ellipse(center + Vector2(-38.0, -35.0), radius_x * 0.48, radius_y * 0.42, Color("5f8170"))
    var peak: PackedVector2Array = PackedVector2Array([
        center + Vector2(-radius_x * 0.55, -radius_y * 0.18),
        center + Vector2(-radius_x * 0.13, -radius_y * 0.72),
        center + Vector2(radius_x * 0.10, -radius_y * 0.15)
    ])
    draw_colored_polygon(peak, Color("728f81"))
    var snow: PackedVector2Array = PackedVector2Array([
        center + Vector2(-radius_x * 0.25, -radius_y * 0.53),
        center + Vector2(-radius_x * 0.13, -radius_y * 0.72),
        center + Vector2(-radius_x * 0.02, -radius_y * 0.46)
    ])
    draw_colored_polygon(snow, Color(0.88, 0.94, 0.93, 0.82))

func _draw_trace_ellipse(center: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
    var points: PackedVector2Array = PackedVector2Array()
    for i in range(49):
        var angle: float = TAU * float(i) / 48.0
        points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
    draw_colored_polygon(points, color)

func _draw_pine_tree(position: Vector2, scale_factor: float) -> void:
    draw_circle(position + Vector2(5.0, 8.0) * scale_factor, 18.0 * scale_factor, Color(0.01, 0.02, 0.02, 0.24))
    draw_rect(Rect2(position.x - 3.0 * scale_factor, position.y + 8.0 * scale_factor, 6.0 * scale_factor, 18.0 * scale_factor), Color("5a4631"))
    var crown1: PackedVector2Array = PackedVector2Array([
        position + Vector2(0, -30) * scale_factor,
        position + Vector2(-22, 11) * scale_factor,
        position + Vector2(22, 11) * scale_factor
    ])
    var crown2: PackedVector2Array = PackedVector2Array([
        position + Vector2(0, -19) * scale_factor,
        position + Vector2(-27, 21) * scale_factor,
        position + Vector2(27, 21) * scale_factor
    ])
    draw_colored_polygon(crown2, Color("173f36"))
    draw_colored_polygon(crown1, Color("27604d"))

func _draw_cabin(position: Vector2, rotation_angle: float) -> void:
    draw_set_transform(position, rotation_angle)
    draw_rect(Rect2(-31.0, -21.0, 64.0, 45.0), Color(0.01, 0.02, 0.02, 0.24))
    draw_rect(Rect2(-34.0, -26.0, 62.0, 43.0), Color("9d3d31"))
    draw_rect(Rect2(-24.0, -17.0, 14.0, 13.0), Color("dbe8e5"))
    draw_rect(Rect2(5.0, -17.0, 14.0, 13.0), Color("dbe8e5"))
    draw_rect(Rect2(-4.0, -2.0, 14.0, 19.0), Color("4a3126"))
    draw_line(Vector2(-39.0, -28.0), Vector2(-4.0, -44.0), Color("332b28"), 8.0, true)
    draw_line(Vector2(-4.0, -44.0), Vector2(34.0, -27.0), Color("332b28"), 8.0, true)
    draw_set_transform(Vector2.ZERO)

func _draw_boat(position: Vector2, rotation_angle: float) -> void:
    draw_set_transform(position, rotation_angle)
    draw_colored_polygon(PackedVector2Array([Vector2(-24,-7), Vector2(23,-7), Vector2(14,8), Vector2(-18,8)]), Color("eef2ee"))
    draw_rect(Rect2(-6.0, -13.0, 18.0, 9.0), Color("b63c35"))
    draw_line(Vector2(-30.0, 12.0), Vector2(28.0, 12.0), Color(0.65, 0.86, 0.90, 0.20), 4.0, true)
    draw_set_transform(Vector2.ZERO)

func _draw_track() -> void:
    var data: Dictionary = _track_data()
    var center: Vector2 = data["center"]
    var outer_x: float = float(data["outer_x"])
    var outer_y: float = float(data["outer_y"])
    var inner_x: float = float(data["inner_x"])
    var inner_y: float = float(data["inner_y"])
    var mid_x: float = (outer_x + inner_x) * 0.5
    var mid_y: float = (outer_y + inner_y) * 0.5
    var half_x: float = (outer_x - inner_x) * 0.5 * road_width_scale
    var half_y: float = (outer_y - inner_y) * 0.5 * road_width_scale
    var adjusted_outer_x: float = mid_x + half_x
    var adjusted_outer_y: float = mid_y + half_y
    var adjusted_inner_x: float = maxf(40.0, mid_x - half_x)
    var adjusted_inner_y: float = maxf(40.0, mid_y - half_y)
    var outer_points: PackedVector2Array = PackedVector2Array()
    var inner_points: PackedVector2Array = PackedVector2Array()
    for i in range(129):
        var angle: float = TAU * float(i) / 128.0
        outer_points.append(center + Vector2(cos(angle) * adjusted_outer_x, sin(angle) * adjusted_outer_y))
        inner_points.append(center + Vector2(cos(angle) * adjusted_inner_x, sin(angle) * adjusted_inner_y))

    # Deep shadow and vegetation shoulder add separation from the water.
    draw_polyline(outer_points, Color(0.01, 0.02, 0.02, 0.34), 98.0, true)
    draw_polyline(inner_points, Color(0.01, 0.02, 0.02, 0.28), 86.0, true)
    draw_polyline(outer_points, Color("2b5a45"), 86.0, true)
    draw_polyline(inner_points, Color("2b5a45"), 74.0, true)

    # Kerb bed, asphalt and subtle asphalt highlight.
    draw_polyline(outer_points, Color("b7b9b3"), 48.0, true)
    draw_polyline(inner_points, Color("b7b9b3"), 48.0, true)
    draw_polyline(outer_points, Color("40484a"), 37.0, true)
    draw_polyline(inner_points, Color("40484a"), 37.0, true)
    draw_polyline(outer_points, Color(0.55, 0.60, 0.61, 0.25), 3.0, true)
    draw_polyline(inner_points, Color(0.55, 0.60, 0.61, 0.25), 3.0, true)

    # Red/white kerb markers placed around both edges.
    for i in range(0, 128, 4):
        var a: Vector2 = outer_points[i]
        var b: Vector2 = outer_points[mini(i + 2, 128)]
        var c: Color = Color("d94d43") if (i / 4) % 2 == 0 else Color("f1eee7")
        draw_line(a, b, c, 9.0, true)
        var ia: Vector2 = inner_points[i]
        var ib: Vector2 = inner_points[mini(i + 2, 128)]
        draw_line(ia, ib, c, 9.0, true)

    # Road texture / tyre wear along the racing corridor.
    for i in range(0, 128, 6):
        var p_outer: Vector2 = outer_points[i]
        var p_inner: Vector2 = inner_points[i]
        var mid: Vector2 = p_outer.lerp(p_inner, 0.50)
        var next_mid: Vector2 = outer_points[mini(i + 2, 128)].lerp(inner_points[mini(i + 2, 128)], 0.50)
        draw_line(mid, next_mid, Color(0.08, 0.10, 0.10, 0.24), 5.0, true)

    # Broken centre guideline, subtle enough to keep the racing line readable.
    for i in range(0, 124, 8):
        var lane_a: Vector2 = outer_points[i].lerp(inner_points[i], 0.50)
        var lane_b: Vector2 = outer_points[i + 3].lerp(inner_points[i + 3], 0.50)
        draw_line(lane_a, lane_b, Color(0.92, 0.91, 0.82, 0.50), 2.2, true)

    # Asphalt flecks and repaired patches add scale without external textures.
    for i in range(0, 128, 5):
        var lane_mid: Vector2 = outer_points[i].lerp(inner_points[i], 0.50)
        var radial: Vector2 = (outer_points[i] - inner_points[i]).normalized()
        var offset_value: float = float(((i * 37) % 29) - 14)
        var mark_start: Vector2 = lane_mid + radial * offset_value
        var next_i: int = mini(i + 1, 128)
        var tangent: Vector2 = outer_points[next_i].lerp(inner_points[next_i], 0.50) - lane_mid
        if tangent.length() > 0.01:
            tangent = tangent.normalized()
            draw_line(mark_start, mark_start + tangent * float(10 + ((i * 11) % 22)), Color(0.12, 0.14, 0.14, 0.20), 1.5, true)

    var gravel_zone: Rect2 = data["gravel"]
    draw_rect(gravel_zone, Color("74634d"))
    for i in range(16):
        var gx: float = gravel_zone.position.x + 8.0 + float((i * 31) % int(maxf(16.0, gravel_zone.size.x - 16.0)))
        var gy: float = gravel_zone.position.y + 8.0 + float((i * 47) % int(maxf(16.0, gravel_zone.size.y - 16.0)))
        draw_circle(Vector2(gx, gy), 3.0, Color(0.80, 0.74, 0.63, 0.35))

    # Start grid and roadside guard rail posts.
    draw_line(start_position + Vector2(-84.0, 0.0), start_position + Vector2(84.0, 0.0), Color("ffffff"), 13.0, true)
    for i in range(8):
        var x: float = start_position.x - 80.0 + float(i) * 20.0
        draw_rect(Rect2(x, start_position.y - 13.0, 10.0, 26.0), Color("111111") if i % 2 == 0 else Color("ffffff"))
    for i in range(0, 128, 10):
        var edge: Vector2 = outer_points[i]
        var inward: Vector2 = (center - edge).normalized()
        var post: Vector2 = edge - inward * 24.0
        draw_circle(post + Vector2(2.0, 3.0), 5.0, Color(0.0, 0.0, 0.0, 0.20))
        draw_circle(post, 4.0, Color("d9ddd9"))

func _draw_paths() -> void:
    if show_raw_path and raw_points.size() > 1:
        draw_polyline(raw_points, Color(1.0, 1.0, 1.0, 0.28), 4.0, true)
    if driving_path.size() < 2:
        return
    for i in range(driving_path.size() - 1):
        var hint: float = speed_hints[mini(i, speed_hints.size() - 1)]
        var line_color: Color = Color("ef5b4c")
        if hint > 0.78:
            line_color = Color("3ee39b")
        elif hint > 0.50:
            line_color = Color("f0c84b")
        draw_line(driving_path[i], driving_path[i + 1], Color(line_color.r, line_color.g, line_color.b, 0.18), 13.0, true)
        draw_line(driving_path[i], driving_path[i + 1], line_color, 5.0, true)


func _draw_skid_marks() -> void:
    if skid_marks.size() < 2:
        return
    draw_polyline(skid_marks, Color(0.05, 0.06, 0.06, 0.42), 5.0, true)

func _draw_ghost() -> void:
    if not ghost_enabled or best_ghost_samples.size() < 2 or not racing or race_time <= 0.0:
        return
    var ratio: float = 0.0
    if best_time > 0.0:
        ratio = clampf(race_time / best_time, 0.0, 1.0)
    var ghost_index: int = mini(int(ratio * float(best_ghost_samples.size() - 1)), best_ghost_samples.size() - 1)
    var ghost_position: Vector2 = best_ghost_samples[ghost_index]
    draw_circle(ghost_position, 21.0, Color(0.45, 0.85, 1.0, 0.20))
    draw_circle(ghost_position, 10.0, Color(0.65, 0.92, 1.0, 0.65))

func _draw_car() -> void:
    var visual_offset: Vector2 = Vector2(0.0, body_roll * 9.0)
    draw_set_transform(car_position, car_rotation + body_roll * 0.06, Vector2(0.82, 0.82))

    # Soft contact shadow under the sprite.
    _draw_trace_ellipse(Vector2(4.0, 6.0) + visual_offset, 46.0, 20.0, Color(0.0, 0.0, 0.0, 0.32))

    if car_texture != null:
        var car_rect: Rect2 = Rect2(-49.0, -25.0 + visual_offset.y, 98.0, 50.0)
        draw_texture_rect(car_texture, car_rect, false)
        # Small highlight and lamp glow make the sprite read on dark asphalt.
        draw_line(Vector2(-13.0, -20.0) + visual_offset, Vector2(24.0, -19.0) + visual_offset, Color(0.70, 0.88, 1.0, 0.16), 2.0, true)
        draw_circle(Vector2(42.0, -13.0) + visual_offset, 3.5, Color(1.0, 0.94, 0.70, 0.45))
        draw_circle(Vector2(42.0, 13.0) + visual_offset, 3.5, Color(1.0, 0.94, 0.70, 0.45))
    else:
        # Fallback if the texture cannot be loaded.
        var body: PackedVector2Array = PackedVector2Array([
            Vector2(-36.0, -16.0) + visual_offset,
            Vector2(18.0, -18.0) + visual_offset,
            Vector2(39.0, -9.0) + visual_offset,
            Vector2(39.0, 9.0) + visual_offset,
            Vector2(18.0, 18.0) + visual_offset,
            Vector2(-36.0, 16.0) + visual_offset
        ])
        draw_colored_polygon(body, Color("176fc1"))

    if tyre_load > 0.85:
        var intensity: float = clampf((tyre_load - 0.85) / 0.60, 0.0, 1.0)
        draw_circle(Vector2(-36.0, -13.0) + visual_offset, 7.0 + intensity * 5.0, Color(0.82, 0.88, 0.88, 0.10 + intensity * 0.18))
        draw_circle(Vector2(-36.0, 13.0) + visual_offset, 7.0 + intensity * 5.0, Color(0.82, 0.88, 0.88, 0.10 + intensity * 0.18))

    draw_set_transform(Vector2.ZERO)

func _draw_countdown_overlay() -> void:
    if countdown_active:
        draw_circle(Vector2(540.0, 930.0), 82.0, Color(0.01, 0.02, 0.03, 0.80))
        draw_circle(Vector2(540.0, 930.0), 67.0, Color(0.95, 0.37, 0.22, 0.90))
        draw_string(ThemeDB.fallback_font, Vector2(470.0, 966.0), str(countdown_value), HORIZONTAL_ALIGNMENT_CENTER, 140.0, 90, Color("ffffff"))
    elif go_flash_time > 0.0:
        var alpha: float = clampf(go_flash_time / 0.65, 0.0, 1.0)
        draw_string(ThemeDB.fallback_font, Vector2(360.0, 960.0), "GO!", HORIZONTAL_ALIGNMENT_CENTER, 360.0, 96, Color(0.35, 1.0, 0.62, alpha))

func _draw_ui() -> void:
    draw_rect(Rect2(0.0, 0.0, 1080.0, 180.0), Color(0.02, 0.05, 0.07, 0.97))
    draw_string(ThemeDB.fallback_font, Vector2(45.0, 68.0), "TRACE RACE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 46, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(45.0, 118.0), "FJORD GAMES - TRACE RACE HD", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color("9cb1b7"))
    draw_string(ThemeDB.fallback_font, Vector2(720.0, 68.0), "TIME %.2f" % race_time, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, Color("ffffff"))
    var best_label: String = "BEST --"
    if best_time > 0.0:
        best_label = "BEST %.2f" % best_time
    draw_string(ThemeDB.fallback_font, Vector2(720.0, 112.0), best_label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, Color("9cb1b7"))

    _draw_button(track_button, str(_track_data()["name"]), Color("28404a"))
    _draw_button(narrow_button, "NARROW", Color("34484f"))
    _draw_button(wide_button, "WIDE", Color("34484f"))

    draw_rect(Rect2(0.0, 1580.0, 1080.0, 340.0), Color(0.02, 0.05, 0.07, 0.98))
    draw_string(ThemeDB.fallback_font, Vector2(50.0, 1638.0), message, HORIZONTAL_ALIGNMENT_LEFT, 980.0, 25, Color("ffffff"))
    _draw_button(undo_button, "UNDO", Color("34484f"))
    _draw_button(clear_button, "CLEAR", Color("34484f"))
    var race_color: Color = Color("167f69")
    if not _validate_path().is_empty():
        race_color = Color("3d4c50")
    _draw_button(race_button, "RACE", race_color)
    _draw_button(telemetry_button, "TELEMETRY %s" % ("ON" if telemetry_enabled else "OFF"), Color("28404a"))
    _draw_button(raw_button, "RAW PATH %s" % ("ON" if show_raw_path else "OFF"), Color("28404a"))
    _draw_button(ghost_button, "BEST GHOST %s" % ("ON" if ghost_enabled else "OFF"), Color("28404a"))

    if telemetry_enabled:
        _draw_telemetry()

func _draw_telemetry() -> void:
    var panel: Rect2 = Rect2(35.0, 205.0, 330.0, 345.0)
    draw_rect(panel, Color(0.02, 0.05, 0.07, 0.82))
    var speed: float = car_velocity.length()
    var path_quality: float = 0.0
    if raw_points.size() > 0:
        path_quality = clampf(float(driving_path.size()) / float(raw_points.size()), 0.0, 1.0)
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 250.0), "SURFACE  %s" % current_surface, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 286.0), "SPEED    %.0f" % speed, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 322.0), "RAW      %d" % raw_points.size(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 358.0), "SMOOTH   %d" % driving_path.size(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 394.0), "QUALITY  %.0f%%" % (path_quality * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 430.0), "TYRE LOAD %.0f%%" % (tyre_load * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 466.0), "SLIP     %.1f°" % rad_to_deg(slip_angle), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 502.0), "BODY ROLL %.0f%%" % (absf(body_roll) / 0.30 * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))
    draw_string(ThemeDB.fallback_font, Vector2(55.0, 538.0), "ROAD WIDTH %.0f%%" % (road_width_scale * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color("ffffff"))

func _draw_button(rect: Rect2, label: String, color: Color) -> void:
    draw_style_box(_rounded_box(color, 18.0), rect)
    draw_string(ThemeDB.fallback_font, rect.position + Vector2(0.0, rect.size.y * 0.64), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 20, Color("ffffff"))

func _rounded_box(color: Color, radius: float) -> StyleBoxFlat:
    var box: StyleBoxFlat = StyleBoxFlat.new()
    box.bg_color = color
    box.corner_radius_top_left = int(radius)
    box.corner_radius_top_right = int(radius)
    box.corner_radius_bottom_left = int(radius)
    box.corner_radius_bottom_right = int(radius)
    return box
