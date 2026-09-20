extends GutTest

## The shotgun guard for [CommandRegistry] (#999): every concrete [Command]
## under `command/` is registered ONCE, with both halves of its entry — the
## deserialiser the codec needs and the handler the applier needs. A verb that
## lands without its registration line fails here, not in a live game.


const COMMAND_DIR := "res://command/"


## Every `*_command.gd` under `command/` that carries a `TAG` — the abstract
## bases (`command.gd`, `node_command.gd`) have none and are skipped.
static func _concrete_command_scripts() -> Dictionary:
	var scripts := {}
	var dir := DirAccess.open(COMMAND_DIR)
	assert(dir != null)
	for file in dir.get_files():
		if not file.ends_with("_command.gd"):
			continue
		var script: GDScript = load(COMMAND_DIR + file)
		var tag: Variant = script.get_script_constant_map().get("TAG")
		if tag == null:
			continue
		scripts[StringName(tag)] = script
	return scripts


func test_the_glob_finds_the_verbs() -> void:
	var scripts := _concrete_command_scripts()
	assert_gt(scripts.size(), 10, "the glob sees the command scripts")
	assert_true(scripts.has(AllocateCommand.TAG))
	assert_true(scripts.has(LaunchAttackCommand.TAG))


func test_every_command_tag_decodes_to_its_own_type() -> void:
	var scripts := _concrete_command_scripts()
	for tag: StringName in scripts:
		var script: GDScript = scripts[tag]
		assert_true(CommandRegistry.has(tag), "registered: %s" % tag)
		var back := CommandRegistry.decode({"type": tag})
		assert_not_null(back, "decodes: %s" % tag)
		if back != null:
			assert_eq(back.get_script(), script, "%s decodes to its own type" % tag)
			assert_eq(back.type_tag(), tag)


func test_every_command_tag_has_a_handler() -> void:
	var scripts := _concrete_command_scripts()
	for tag: StringName in scripts:
		var handler := CommandRegistry.handler_for_tag(tag)
		assert_not_null(handler, "handler for %s" % tag)
		if handler != null:
			assert_true(handler is CommandHandler, "%s handler is a CommandHandler" % tag)


func test_the_registry_knows_no_verb_the_glob_does_not() -> void:
	var scripts := _concrete_command_scripts()
	for tag: StringName in CommandRegistry.tags():
		assert_true(scripts.has(tag), "registered tag %s has a command script" % tag)


func test_unknown_tag_has_no_entry() -> void:
	assert_false(CommandRegistry.has(&"teleport"))
	assert_null(CommandRegistry.handler_for_tag(&"teleport"))
	assert_null(CommandRegistry.decode({"type": &"teleport"}))
