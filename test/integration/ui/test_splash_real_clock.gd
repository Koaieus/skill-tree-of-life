extends GutTest

## The ONE real-clock run of the splash (#1066 keeper; #854's cold-cache case).
## Every timing assert lives in `test/unit/ui/test_splash.gd`, stepped through
## the splash's `clock`; this script is the single proof that the charge chain
## BOOMs and the settle departs when the real frame loop moves the tweens —
## the root lit, focus on it, navigation unlocked. Generous budget, no pacing
## assert: a fat first frame on a cold `.godot` cache must not fail it.

const _SPLASH := preload("res://ui/frontmatter/splash_screen.tscn")
const _FRONTMATTER := preload("res://ui/frontmatter/frontmatter_root.tscn")

var _frontmatter: FrontmatterRoot
var _splash: SplashScreen


func before_each() -> void:
	_frontmatter = _FRONTMATTER.instantiate()
	add_child_autofree(_frontmatter)
	_frontmatter.reduce_motion = false
	_splash = _SPLASH.instantiate()
	_splash.frontmatter_path = _frontmatter.get_path()
	_splash.charge_duration = 0.1
	_splash.settle_pause = 0.05
	add_child_autofree(_splash)


func test_the_press_booms_and_settles_on_the_real_clock() -> void:
	var root := _frontmatter.tree.root
	_splash.advance()
	var settled := func() -> bool:
		return _frontmatter.focus_id == root \
				and _frontmatter.view_for(root).allocated \
				and not _frontmatter.navigation_locked
	assert_true(await wait_until(settled, 15.0),
			"the charge BOOMs, the root reads lit and the menu is steerable again")
