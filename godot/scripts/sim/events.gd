extends RefCounted
## Things the sim tells the outside world about during a step. Each event is a Dictionary:
## {"kind": Kind, ...fields}. Positions are world x/z. Presenters (view, audio, HUD, recorder) subscribe;
## the sim never calls them. Per-frame positions are read from sim state, not from events.

enum Kind {
	FIRED,            ## weapon, x, z, bullets
	POOL_EXHAUSTED,   ## pool, wanted
	ENEMY_SPAWNED,    ## serial, enemy, x, z
	ENEMY_HIT,        ## serial, enemy, x, z, amount, source
	ENEMY_KILLED,     ## serial, enemy, x, z, amount, source, score_gain, combo
	ENEMY_ESCAPED,    ## serial, enemy
	PLAYER_HURT,      ## amount, absorbed, hp, armor, source
	COMBO_BROKEN,     ## combo
	UPGRADE_SPAWNED,  ## serial, reward, kind, x, z
	ICE_HIT,          ## serial, x, z, amount, ice_hp
	ICE_SHATTERED,    ## serial, reward, x, z
	UPGRADE_EXPIRED,  ## serial, reward, thawed
	PICKUP,           ## serial, reward, kind, x, z
	TOWER_DEPLOYED,   ## serial, tower, x, z
	TOWER_EXPIRED,    ## serial, tower
	BOSS_STARTED,     ## wave, hp
	BOSS_HIT,         ## x, z, amount, hp, max_hp
	BOSS_CONTACT,     ## damage
	BOSS_WRAPPED,     ## wave (boss passed the player and comes round again)
	BOSS_DEFEATED,    ## wave, x, z, score_gain
	GAME_OVER,        ## score, distance, kills
}

## Damage sources, for ENEMY_HIT / ENEMY_KILLED / PLAYER_HURT.
const SOURCES := ["bullet", "splash", "burn", "poison", "enemy", "boss"]


static func kind_name(kind: int) -> String:
	return Kind.keys()[kind]
