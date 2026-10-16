extends RefCounted
## Things the sim tells the outside world about during a step. Each event is a Dictionary:
## {"kind": Kind, ...fields}. Positions are world x/z. Presenters (view, audio, HUD, recorder) subscribe;
## the sim never calls them. Per-frame positions are read from sim state, not from events.

enum Kind {
	FIRED,            ## weapon, x, z, bullets
	POOL_EXHAUSTED,   ## pool, wanted
	ENEMY_SPAWNED,    ## serial, enemy, x, z
	ENEMY_HIT,        ## serial, enemy, x, z, amount, source, weapon
	ENEMY_KILLED,     ## serial, enemy, x, z, amount, source, weapon, score_gain, combo
	ENEMY_ESCAPED,    ## serial, enemy
	PLAYER_HURT,      ## amount, absorbed, hp, armor, source, by, by_x, player_x, weapon, distance
	COMBO_BROKEN,     ## combo
	UPGRADE_SPAWNED,  ## serial, reward, reward_kind, x, z
	ICE_HIT,          ## serial, x, z, amount, ice_hp
	ICE_SHATTERED,    ## serial, reward, x, z
	UPGRADE_EXPIRED,  ## serial, reward, thawed
	PICKUP,           ## serial, reward, reward_kind, x, z
	GUN_CHANGED,      ## action (levelled|maxed|added|replaced), slot, gun, level, replaced, x, z
	TOWER_DEPLOYED,   ## serial, tower, x, z
	TOWER_EXPIRED,    ## serial, tower
	BOSS_STARTED,     ## wave, hp, boss (bosses.tsv id), name
	BOSS_HIT,         ## x, z, amount, hp, max_hp
	BOSS_CONTACT,     ## damage
	BOSS_WRAPPED,     ## wave (boss passed the player and comes round again)
	BOSS_DEFEATED,    ## wave, x, z, score_gain
	GAME_OVER,        ## score, distance, kills
	LEVEL_UP,         ## level, choices (perk ids) - the game waits for a pick
	PERK_TAKEN,       ## perk, stacks, level
	EXPLOSION,        ## x, z, radius, weapon, impact (false = detonated at the end of its range)
	TRAP_SPAWNED,     ## serial, trap, x, z
	TRAP_HIT,         ## serial, x, z, amount, hp
	TRAP_DESTROYED,   ## serial, trap, x, z (shot to pieces: no effect)
	TRAP_TRIGGERED,   ## serial, trap, effect, seconds, x, z (the player touched it)
	TRAP_EXPIRED,     ## serial, trap (left the road behind the player)
	CRIT,             ## x, z, amount, enemy (Lucky Shot doubled this hit)
	UPGRADE_LOST,     ## serial, reward, x, z (its pair partner was freed first: pick one, lose the other)
	BOSS_SUMMONED,    ## boss, x, z, count (minions it called in; count 0 = enemy pool full)
	BOSS_SHOT,        ## boss, x, z (a shot left the boss; its flight is read from boss.shots)
}

## Damage sources, for ENEMY_HIT / ENEMY_KILLED / PLAYER_HURT.
const SOURCES := ["bullet", "splash", "burn", "poison", "enemy", "boss"]


static func kind_name(kind: int) -> String:
	return Kind.keys()[kind]
