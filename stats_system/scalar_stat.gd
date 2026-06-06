@tool
class_name ScalarStat
extends Stat

## Concrete leaf for scalar stats. `Stat` itself is abstract so the inspector
## doesn't offer "New Stat" alongside "New PoolStat" — board scalar @exports
## (strength, dexterity, …) are typed as ScalarStat, board pool @exports as
## PoolStat, and each dropdown shows exactly the option it should.
##
## Empty by design. All scalar behaviour lives on Stat.
