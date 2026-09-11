extends GutTest

## The spell catalogue (#853) — every authored spell, long-form, read-only.
##
## Three claims, one per surface it touches: the modal body lists
## [constant SpellCatalog.ALL] in order with each spell's tagline, description
## and the SAME four derived sections the tooltip renders ([SpellSections] is
## the one derivation — a caster-less build, so nothing is gold); the pause
## menu exposes the entry point; the frontmatter names a leaf for it and
## supplies the panel that leaf asks for.

const _BODY := preload("res://ui/spell_catalogue/spell_catalogue_body.tscn")
const _MODAL := preload("res://ui/spell_catalogue/spell_catalogue_modal.tscn")
const _PANEL := preload("res://ui/spell_catalogue/spell_catalogue_panel.tscn")
const _PAUSE_MENU := preload("res://ui/pause_menu.tscn")
const _HUD_ROOT := preload("res://ui/hud/hud_root.tscn")
const _FRONTMATTER_PANELS := preload("res://ui/frontmatter/panels/frontmatter_panels.tscn")

const _SECTION_NAMES: Array[String] = [
	"%CastSection", "%OnArrivalSection", "%ThenSection", "%CritsSection",
]


func after_each() -> void:
	get_tree().paused = false


func _populated_body() -> SpellCatalogueBody:
	var body: SpellCatalogueBody = _BODY.instantiate()
	add_child_autofree(body)
	body.populate(null)
	return body


# --- the body: every spell, in order, long-form ------------------------------

func test_body_lists_every_authored_spell_in_catalogue_order() -> void:
	var entries := _populated_body().entries()
	assert_eq(entries.size(), SpellCatalog.ALL.size(), "one entry per authored spell")
	for i in mini(entries.size(), SpellCatalog.ALL.size()):
		assert_same(entries[i].spell, SpellCatalog.ALL[i],
				"entry %d should be %s" % [i, SpellCatalog.ALL[i].id])


func test_each_entry_shows_its_spells_tagline_and_description_verbatim() -> void:
	for entry in _populated_body().entries():
		var spell := entry.spell
		assert_eq(entry.tagline_text(), spell.tagline, "%s: tagline" % spell.id)
		assert_eq(entry.description_text(), spell.description, "%s: description" % spell.id)
		assert_string_contains(entry.header_text(), spell.name.to_upper())
		assert_string_contains(entry.mana_text(), str(spell.mana_cost))


func test_each_entry_binds_the_same_four_sections_the_tooltip_derives() -> void:
	# One derivation, no second implementation: the catalogue renders exactly
	# what a caster-less SpellSections.build says, section for section — and
	# with no caster nothing may wear the gold "this is yours" accent.
	for entry in _populated_body().entries():
		var expected := SpellSections.build(entry.spell, null)
		var expected_lines := [
			expected.cast.lines, expected.on_arrival.lines,
			expected.then.lines, expected.crits.lines,
		]
		for i in _SECTION_NAMES.size():
			var section := entry.get_node(_SECTION_NAMES[i]) as SpellTooltipSection
			assert_not_null(section, "%s: %s must be the section scene"
					% [entry.spell.id, _SECTION_NAMES[i]])
			if section == null:
				continue
			assert_eq(section.line_texts(), expected_lines[i],
					"%s: %s" % [entry.spell.id, _SECTION_NAMES[i]])
			for row in section.get_node("%Rows").get_children():
				assert_false((row as SpellTooltipLine).dynamic,
						"%s: no caster, so nothing is gold" % entry.spell.id)


func test_body_needs_no_selection_and_closes_on_confirm() -> void:
	var body := _populated_body()
	assert_true(body.is_selection_valid(), "there is nothing to pick — CLOSE is always live")
	assert_eq(body.resolve(), [], "nothing is chosen")
	assert_string_contains(body.status_text(), str(SpellCatalog.ALL.size()))


func test_modal_is_a_cancellable_modal_base_that_presents_the_body() -> void:
	var modal: SpellCatalogueModal = _MODAL.instantiate()
	add_child_autofree(modal)
	assert_true(modal.cancellable, "Esc / right-click must close a read-only surface")
	var closed := [0]
	modal.closed.connect(func() -> void: closed[0] += 1)
	modal.present()
	assert_true(modal.visible)
	var body := modal.get_node("%BodySlot").get_child(0) as SpellCatalogueBody
	assert_not_null(body, "the body slot holds the catalogue body")
	assert_eq(body.entries().size(), SpellCatalog.ALL.size())
	modal.get_node("%ConfirmButton").pressed.emit()
	assert_false(modal.visible, "CLOSE takes it down")
	assert_eq(closed[0], 1, "closed fires exactly once")


# --- the pause menu entry ----------------------------------------------------

func test_pause_menu_exposes_the_catalogue_and_asks_rather_than_opening() -> void:
	var menu: PauseMenu = _PAUSE_MENU.instantiate()
	add_child_autofree(menu)
	var button := menu.get_node("%SpellCatalogueButton") as Button
	assert_not_null(button, "the pause menu has a Spell catalogue item")
	if button == null:
		return
	var asked := [0]
	menu.spell_catalogue_requested.connect(func() -> void: asked[0] += 1)
	button.pressed.emit()
	assert_eq(asked[0], 1, "the menu emits; HudRoot owns the modal queue")


func test_hud_root_mounts_the_modal_under_the_tooltip() -> void:
	# Sibling order under HudRoot is z-order (#765): the catalogue is a modal
	# like the other three and the tooltip must still draw above it.
	var hud: HudRoot = _HUD_ROOT.instantiate()
	var modal := hud.get_node_or_null("SpellCatalogueModal")
	assert_not_null(modal, "HudRoot should mount a SpellCatalogueModal")
	if modal != null:
		assert_is(modal, SpellCatalogueModal)
		assert_gt(hud.get_node("SpellTooltip").get_index(), modal.get_index(),
				"SpellTooltip must sit after (draw above) the catalogue")
	hud.queue_free()


# --- the frontmatter entry ---------------------------------------------------

func test_menu_tree_names_a_root_leaf_that_opens_the_catalogue_panel() -> void:
	var tree := MenuGraph.build()
	assert_true(tree.has(MenuGraph.ID_SPELL_CATALOGUE), "the tree has a catalogue leaf")
	if not tree.has(MenuGraph.ID_SPELL_CATALOGUE):
		return
	var item := tree.get_item(MenuGraph.ID_SPELL_CATALOGUE)
	assert_true(item.is_leaf())
	assert_eq(item.parent, MenuGraph.ID_ROOT, "it hangs off the root, beside OPTIONS")
	assert_eq(item.panel, MenuGraph.PANEL_SPELL_CATALOGUE)
	assert_null(item.route, "reading the catalogue is not a route into a run")
	assert_not_null(FrontmatterLayout.look_of(MenuGraph.ID_SPELL_CATALOGUE),
			"the root fan authors a seat for it")


func test_frontmatter_panels_supply_the_catalogue_panel_with_every_spell() -> void:
	var panels: FrontmatterPanels = _FRONTMATTER_PANELS.instantiate()
	add_child_autofree(panels)
	assert_true(panels.has_panel(MenuGraph.PANEL_SPELL_CATALOGUE))
	var panel := panels.get_panel(MenuGraph.PANEL_SPELL_CATALOGUE) as SpellCataloguePanel
	assert_not_null(panel, "the registered panel is the catalogue panel")
	if panel == null:
		return
	assert_eq(panel.entries().size(), SpellCatalog.ALL.size(),
			"the meta menu shows the same list, populated on its own")
	assert_string_contains(panel.title.to_upper(), "SPELL")
