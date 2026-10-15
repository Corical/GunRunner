extends "res://scripts/ports/controls.gd"
## The headless batch bot, steering the windowed game (used to drive and record the game without a person).

const Bot = preload("res://scripts/batch/simple_bot.gd")

var _bot := Bot.new()


func read(sim: Object) -> Dictionary:
	var inp := {"move": _bot.decide(sim)}
	if not sim.choices.is_empty():
		inp["pick"] = _bot.pick(sim)
	return inp


func name() -> String:
	return "bot"
