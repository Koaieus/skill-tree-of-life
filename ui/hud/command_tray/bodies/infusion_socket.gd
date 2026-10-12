@tool
class_name InfusionSocket
extends Control

enum State { EMPTY, FILLED, LOCKED }

signal toggled(index: int)
signal cleared(index: int)

var index: int = 0
var state: State = State.EMPTY


func line_text() -> String:
	return ""
