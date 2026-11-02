class_name Glow
extends RefCounted
## 全屏泛光（bloom）后处理。
##
## 项目此前是纯 LDR 绘制：金色描边、粒子、水印无论 alpha 加多高都只是"半透明色片"，
## 永远不会真的亮起来。这里用一个 WorldEnvironment 把 glow 挂到视口上，
## 配合 Rendering > Viewport > HDR 2D，让颜色值 > 1.0 的像素（见 UiTheme.hot）产生泛光。
##
## 只在 Forward+ / Mobile 渲染器下启用；gl_compatibility 不支持 2D glow，直接跳过。

const NODE_NAME := "GlowEnv"

## 总开关：低端机如果觉得发热/掉帧，把这里改成 false 即可整体关闭（其余代码无需改动）
const ENABLED := true

static var _installed: bool = false


## 当前渲染器是否支持 2D glow
static func available() -> bool:
	if not ENABLED:
		return false
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## 把 WorldEnvironment 挂到 host（通常是界面根节点），整个视口共享同一个环境。
## 重复调用无副作用；不支持的平台静默跳过。
static func install(host: Node) -> void:
	if not available():
		return
	if host == null or not host.is_inside_tree():
		return
	if _installed or host.has_node(NodePath(NODE_NAME)):
		return
	_installed = true

	var env := Environment.new()
	# 2D 画面要作为背景被后处理链取到，必须用 Canvas 背景模式
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	# 只让真正的 HDR 像素（>1.0）发光，避免整个画面糊掉
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 3.5
	env.glow_normalized = false

	# 泛光只取中小半径的几层：够柔，又不会把整屏糊成一片
	for i in range(1, 8):
		env.set("glow_levels/%d" % i, 0.0)
	env.set("glow_levels/2", 1.0)
	env.set("glow_levels/3", 0.55)
	env.set("glow_levels/4", 0.2)

	var we := WorldEnvironment.new()
	we.name = NODE_NAME
	we.environment = env
	host.add_child(we)
