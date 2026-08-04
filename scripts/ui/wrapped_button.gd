class_name WrappedButton
extends RefCounted
## A Button whose caption is a child Label, because Button cannot wrap text.
##
## `Button.autowrap_mode` does not exist in Godot 4.3 — it arrived in 4.4 — and
## assigning an unknown property at runtime raises an error that ABORTS THE
## REST OF THE FUNCTION. Five builders in this project were written as
##
##     button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
##     button.add_theme_font_size_override("font_size", 22)
##     ...
##     button.text = "\n".join(lines)
##
## so the text assignment never ran, and every Policy Card, deductible, site
## option and Headquarters upgrade row shipped as a blank box. Nothing failed
## loudly: the buttons were there, sized, styled, focusable and clickable —
## just empty. The player reported the card draft and the insurance selector as
## blank screens, twice, and both were this.
##
## A Label child fixes it properly rather than by dropping the wrapping: Label
## has had autowrap since forever, handles the explicit newlines these captions
## are built from, and keeps working when the project moves to 4.4.
##
## tools/check_godot_api.py now fails on `autowrap_mode` assigned to anything
## that is not a Label, so the shape cannot come back.

## Matches the content margins on the themed button box in
## assets/ui/theme.tres, so the caption sits inside the border rather than
## under it. Kept here rather than read from the theme because a Label child of
## a non-Container Control is positioned by anchors, not by the stylebox.
const INSET := Vector2(14.0, 10.0)


## A button whose caption wraps. Set the caption with caption() — assigning
## `button.text` directly would draw a second, unwrapped copy over this one.
static func make(font_size: int, wrap: bool = true) -> Button:
	var button := Button.new()
	var label := Label.new()
	label.name = "Caption"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = INSET.x
	label.offset_top = INSET.y
	label.offset_right = -INSET.x
	label.offset_bottom = -INSET.y
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The Button owns the input; the caption must never eat a tap (§6).
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	button.add_child(label)
	return button


static func caption(button: Button, text: String) -> void:
	var label := button.get_node_or_null("Caption") as Label
	if label != null:
		label.text = text
	else:
		button.text = text      # not one of ours; fall back to the plain button


## Tint the caption. Buttons carry their state colour on the text, never on
## modulate — modulate would fade the whole box including its border, which is
## the bug tools/check_text_fit.py exists to catch.
static func tint(button: Button, color: Color) -> void:
	var label := button.get_node_or_null("Caption") as Label
	if label != null:
		label.add_theme_color_override("font_color", color)
