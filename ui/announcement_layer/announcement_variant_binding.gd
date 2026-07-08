class_name AnnouncementVariantBinding
extends Resource

## One entry in [member AnnouncementLayer.variant_bindings]: which
## [enum AnnouncementRequest.Kind] this scene handles. The scene's root must
## extend [AnnouncementBand].

@export var kind: AnnouncementRequest.Kind = AnnouncementRequest.Kind.TITLE
@export var scene: PackedScene
