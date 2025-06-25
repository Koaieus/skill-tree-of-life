extends Resource
class_name StatMetaData

## Full name of a stat
@export var name: String = 'unnamed stat'

## Abbreviation of a stat
@export var abbreviation: String = '---'

## Description of a stat
@export_multiline var description: String = ''

## Ordering amongst stats
@export_range(0, 999) var order: int = 100
