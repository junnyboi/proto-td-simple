extends SceneTree

const CLASSES := [
	"gunner", "mage_apprentice", "swordmaster",
]
const GENDERS := ["female", "male"]
const ACTIONS := ["idle", "attack"]
const DIRECTIONS := ["ne", "nw"]
const SOURCE_CELL_PX := 640
const COLUMNS := 8
const METRIC_CELL_PX := 320
const QUICK_SAMPLE_STRIDE := 4
const FULL_SAMPLE_STRIDE := 8
const MIN_PSNR_DB := 30.0
const MAX_RGB_MAE := 0.017
const MAX_ALPHA_MAE := 0.002
const MIN_EDGE_RATIO := 0.90
const MAX_EDGE_RATIO := 1.10
const QUICK_CASES := [
	"gunner/female/attack_ne",
	"mage_apprentice/male/idle_ne",
	"swordmaster/female/idle_ne",
]

var _failures: Array[String] = []
var _rows: Array[Dictionary] = []
var _sample_stride := QUICK_SAMPLE_STRIDE


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var full := OS.get_environment("ADVANCED_COMPRESSION_FULL") == "1"
	_sample_stride = FULL_SAMPLE_STRIDE if full else QUICK_SAMPLE_STRIDE
	if full:
		for class_id: String in CLASSES:
			for gender: String in GENDERS:
				for action: String in ACTIONS:
					for direction: String in DIRECTIONS:
						_measure("res://assets/sprites/operators/animated/%s/%s/%s_%s.webp" % [class_id, gender, action, direction])
	else:
		for relative_path: String in QUICK_CASES:
			_measure("res://assets/sprites/operators/animated/%s.webp" % relative_path)
	var by_psnr := _rows.duplicate()
	by_psnr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.psnr_db) < float(b.psnr_db))
	var by_mae := _rows.duplicate()
	by_mae.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rgb_mae) > float(b.rgb_mae))
	var by_alpha := _rows.duplicate()
	by_alpha.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.alpha_mae) > float(b.alpha_mae))
	var by_edge := _rows.duplicate()
	by_edge.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return absf(float(a.edge_ratio) - 1.0) > absf(float(b.edge_ratio) - 1.0)
	)
	var worst_psnr: Dictionary = by_psnr[0]
	var worst_mae: Dictionary = by_mae[0]
	var worst_alpha: Dictionary = by_alpha[0]
	var worst_edge: Dictionary = by_edge[0]
	var report := {
		"schema_version": 1,
		"coverage": "full-24" if full else "representative-3",
		"assets": _rows.size(),
		"method": "conservative 320px decoded source/imported-Texture2D proxy, composited over dark and light terrain proxies; not literal BattleView rendering",
		"source_cell_px": SOURCE_CELL_PX,
		"metric_cell_px": METRIC_CELL_PX,
		"sample_stride": _sample_stride,
		"thresholds": {
			"min_psnr_db": MIN_PSNR_DB,
			"max_rgb_mae": MAX_RGB_MAE,
			"max_alpha_mae": MAX_ALPHA_MAE,
			"edge_ratio_range": [MIN_EDGE_RATIO, MAX_EDGE_RATIO],
		},
		"worst": {
			"psnr": worst_psnr,
			"rgb_mae": worst_mae,
			"alpha_mae": worst_alpha,
			"edge_ratio": worst_edge,
		},
		"rows": _rows,
		"failures": _failures,
	}
	var output := OS.get_environment("ADVANCED_COMPRESSION_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			_failures.append("unable to write report %s" % output)
		else:
			file.store_string(JSON.stringify(report, "  ", false) + "\n")
			file.close()
	if _failures.is_empty():
		print("ADVANCED_OPERATOR_COMPRESSION_QUALITY_OK")
		print("assets=%d min_psnr=%.2f max_rgb_mae=%.5f max_alpha_mae=%.6f edge_ratio=%.3f" % [
			_rows.size(), float(worst_psnr.psnr_db), float(worst_mae.rgb_mae), float(worst_alpha.alpha_mae), float(worst_edge.edge_ratio),
		])
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _measure(path: String) -> void:
	var source := Image.load_from_file(ProjectSettings.globalize_path(path))
	var texture := load(path) as Texture2D
	var runtime := texture.get_image() if texture != null else null
	if source == null or source.is_empty() or runtime == null or runtime.is_empty():
		_failures.append("%s could not load source/runtime images" % path)
		return
	if source.get_size() != runtime.get_size():
		_failures.append("%s runtime dimensions differ: %s vs %s" % [path, source.get_size(), runtime.get_size()])
		return
	var rows := 3 if path.contains("/idle_") else 2
	var expected_size := Vector2i(COLUMNS * SOURCE_CELL_PX, rows * SOURCE_CELL_PX)
	if source.get_size() != expected_size:
		_failures.append("%s expected %s source/runtime atlas, got %s" % [path, expected_size, source.get_size()])
		return
	source.resize(COLUMNS * METRIC_CELL_PX, rows * METRIC_CELL_PX, Image.INTERPOLATE_LANCZOS)
	runtime.resize(COLUMNS * METRIC_CELL_PX, rows * METRIC_CELL_PX, Image.INTERPOLATE_LANCZOS)
	var dark_mse := 0.0
	var light_mse := 0.0
	var dark_abs := 0.0
	var light_abs := 0.0
	var alpha_abs := 0.0
	var source_edge := 0.0
	var runtime_edge := 0.0
	var samples := 0
	var measured_pixels := 0
	var edge_samples := 0
	for y: int in range(0, source.get_height(), _sample_stride):
		for x: int in range(0, source.get_width(), _sample_stride):
			var a := source.get_pixel(x, y)
			var b := runtime.get_pixel(x, y)
			alpha_abs += absf(a.a - b.a)
			measured_pixels += 1
			if maxf(a.a, b.a) < 0.03:
				continue
			var source_dark := _composite(a, Color("0c1928"))
			var runtime_dark := _composite(b, Color("0c1928"))
			var source_light := _composite(a, Color("c9c1ae"))
			var runtime_light := _composite(b, Color("c9c1ae"))
			var dark_delta := source_dark - runtime_dark
			var light_delta := source_light - runtime_light
			dark_mse += (dark_delta.r * dark_delta.r + dark_delta.g * dark_delta.g + dark_delta.b * dark_delta.b) / 3.0
			light_mse += (light_delta.r * light_delta.r + light_delta.g * light_delta.g + light_delta.b * light_delta.b) / 3.0
			dark_abs += (absf(dark_delta.r) + absf(dark_delta.g) + absf(dark_delta.b)) / 3.0
			light_abs += (absf(light_delta.r) + absf(light_delta.g) + absf(light_delta.b)) / 3.0
			samples += 1
			if x > 0 and y > 0 and a.a > 0.1 and b.a > 0.1:
				var al := source.get_pixel(x - 1, y)
				var au := source.get_pixel(x, y - 1)
				var bl := runtime.get_pixel(x - 1, y)
				var bu := runtime.get_pixel(x, y - 1)
				source_edge += absf(_luma(source_dark) - _luma(_composite(al, Color("0c1928")))) + absf(_luma(source_dark) - _luma(_composite(au, Color("0c1928"))))
				runtime_edge += absf(_luma(runtime_dark) - _luma(_composite(bl, Color("0c1928")))) + absf(_luma(runtime_dark) - _luma(_composite(bu, Color("0c1928"))))
				edge_samples += 1
	var mse := maxf(dark_mse, light_mse) / maxf(float(samples), 1.0)
	var psnr := 99.0 if mse <= 0.0000000001 else 10.0 * log(1.0 / mse) / log(10.0)
	var rgb_mae := maxf(dark_abs, light_abs) / maxf(float(samples), 1.0)
	var alpha_mae := alpha_abs / maxf(float(measured_pixels), 1.0)
	var edge_ratio := runtime_edge / maxf(source_edge, 0.000001)
	var row := {
		"path": path,
		"psnr_db": snappedf(psnr, 0.001),
		"rgb_mae": snappedf(rgb_mae, 0.000001),
		"alpha_mae": snappedf(alpha_mae, 0.000001),
		"edge_ratio": snappedf(edge_ratio, 0.0001),
		"samples": samples,
		"edge_samples": edge_samples,
	}
	_rows.append(row)
	if psnr < MIN_PSNR_DB or rgb_mae > MAX_RGB_MAE or alpha_mae > MAX_ALPHA_MAE or edge_ratio < MIN_EDGE_RATIO or edge_ratio > MAX_EDGE_RATIO:
		_failures.append("%s quality drift: PSNR %.2f, RGB MAE %.5f, alpha MAE %.6f, edge %.3f" % [path, psnr, rgb_mae, alpha_mae, edge_ratio])


func _luma(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _composite(color: Color, background: Color) -> Color:
	return Color(
		color.r * color.a + background.r * (1.0 - color.a),
		color.g * color.a + background.g * (1.0 - color.a),
		color.b * color.a + background.b * (1.0 - color.a),
		1.0,
	)
