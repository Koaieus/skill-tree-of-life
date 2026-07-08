class_name AnnouncementBand
extends Control

## Contract every AnnouncementLayer variant band must implement. The layer
## instantiates one band per [enum AnnouncementRequest.Kind] (bound via
## [AnnouncementVariantBinding]) and drives it purely through this contract —
## a new visual register becomes "new Kind + new scene", not new plumbing in
## the layer. See [TitleBand] / [CalloutBand] for concrete implementations.

signal finished


## Play [param request]. Must emit [signal finished] exactly once when the
## full display (open + hold + close) completes.
func play(_request: AnnouncementRequest) -> void:
	push_error("AnnouncementBand.play() not overridden by %s" % get_script().resource_path)
