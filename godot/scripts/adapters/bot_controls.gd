extends "res://scripts/ports/controls.gd"
## The headless batch bot, steering the windowed game (used to drive and record the game without a person).

const Bot = preload("res://scripts/batch/simple_bot.gd")

var _bot := Bot.new()


func read(sim: Object) -> Dictionary:
	return {"move": _bot.decide(sim)}


func name() -> String:
	return "bot"
