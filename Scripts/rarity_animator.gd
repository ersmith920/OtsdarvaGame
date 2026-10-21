# Keeps UI in an animated rarity's color (the Mythic rainbow) by calling `apply` with the
# current color every frame. Lives as a child of the UI it colors, so it goes away with it.
# Keeps running while the game is paused (menus are open then).
#
#   RarityAnimator.attach(label, gun.get_rarity(), func(c: Color): label.modulate = c)
class_name RarityAnimator
extends Node

var rarity := Rarity.MYTHIC
var apply : Callable


## Calls apply(color) now, and every frame from then on if the rarity's color is animated.
## Returns the animator node (or null for still colors).
static func attach(parent: Node, p_rarity: int, p_apply: Callable) -> RarityAnimator:
	p_apply.call(Rarity.get_color(p_rarity))
	if not Rarity.is_animated(p_rarity):
		return null
	var anim := RarityAnimator.new()
	anim.rarity = p_rarity
	anim.apply = p_apply
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(anim)
	return anim


func _process(_delta: float) -> void:
	if apply.is_valid():
		apply.call(Rarity.get_color(rarity))
