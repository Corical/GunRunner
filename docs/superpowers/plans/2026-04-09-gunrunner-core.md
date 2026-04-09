# GunRunner — Lane Shooter Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a 3-lane auto-shooting endless runner where enemies approach from ahead, the player positions by lane-switching, and frozen upgrade blocks must be shot open to unlock weapons.

**Architecture:** BabylonJS 3D game with a central GameManager orchestrating a game loop that updates: InputHandler → Player (auto-fire) → BulletManager → EnemyManager → FrozenUpgradeManager → CollisionSystem → UIManager. Entities are simple meshes with position/HP/state. No ECS — plain classes with update(dt) methods. Collision is circle-based (same as CrowdRunner).

**Tech Stack:** BabylonJS 8, TypeScript, Vite

**Already built:**
- `Config.ts` — all game constants, weapon configs, enemy configs, enums
- `SceneManager.ts` — engine, camera, scrolling road, trees, lighting
- `index.html` — full UI layout (HP bar, score, weapon, boss HP, combo, screens)
- Build tooling — package.json, tsconfig, vite.config.ts, node_modules

---

## File Map

| File | Responsibility | Creates/Modifies |
|------|---------------|-----------------|
| `src/main.ts` | Entry point, boots GameManager | Create |
| `src/core/GameManager.ts` | Game loop, state machine, system orchestration | Create |
| `src/systems/InputHandler.ts` | Keyboard + touch → lane direction queue | Create (port from CrowdRunner) |
| `src/entities/Player.ts` | Player mesh, lane position, HP, weapon state | Create |
| `src/entities/Bullet.ts` | Single bullet — position, velocity, damage, mesh | Create |
| `src/systems/BulletManager.ts` | Spawns bullets from player weapon, pools + recycles them | Create |
| `src/entities/Enemy.ts` | Single enemy — type, HP, position, mesh, hit feedback | Create |
| `src/systems/EnemyManager.ts` | Spawns enemy waves, moves them, removes dead/passed | Create |
| `src/entities/FrozenUpgrade.ts` | Ice block with inner reward — has ice HP, thaws on hits | Create |
| `src/systems/FrozenUpgradeManager.ts` | Spawns/moves/tracks frozen upgrades | Create |
| `src/entities/Boss.ts` | Boss entity — huge HP, attack patterns, phases | Create |
| `src/systems/CollisionSystem.ts` | Bullet↔Enemy, Bullet↔Frozen, Enemy↔Player, BossProjectile↔Player | Create |
| `src/systems/SoundSystem.ts` | Procedural Web Audio sounds (shoot, hit, pickup, boss) | Create (port + adapt) |
| `src/systems/ParticleSystem.ts` | Muzzle flash, enemy explosion, ice shatter, boss effects | Create (port + adapt) |
| `src/systems/CameraEffects.ts` | Screen shake, zoom on boss, impact feedback | Create (port from CrowdRunner) |
| `src/systems/FloatingText.ts` | Damage numbers, combo text, pickup labels | Create (port from CrowdRunner) |
| `src/ui/UIManager.ts` | DOM UI updates — HP, score, weapon, combo, boss HP, screens | Create |

---

## Chunk 1: Core Loop + Player + Shooting

Get a player on screen that auto-fires bullets forward. No enemies yet — just the feel of shooting.

### Task 1: InputHandler

**Files:**
- Create: `src/systems/InputHandler.ts`

- [ ] **Step 1: Create InputHandler** — Port from CrowdRunner. Keyboard (arrow/WASD) + touch swipe → LaneDirection queue. Identical logic.

```typescript
// Port CrowdRunner's InputHandler as-is, removing the backtick toggle
```

- [ ] **Step 2: Verify it compiles**

Run: `npx tsc --noEmit`

- [ ] **Step 3: Commit**

```
git add src/systems/InputHandler.ts
git commit -m "🏗️ feat: add InputHandler (ported from CrowdRunner)"
```

---

### Task 2: Player Entity

**Files:**
- Create: `src/entities/Player.ts`

The player is a character mesh at z=-8, switches between 3 lanes, has HP, holds a weapon, and auto-fires.

- [ ] **Step 1: Create Player class**

```typescript
class Player {
  // State: position (Vector3), currentLane, targetLane, hp, weapon
  // Mesh: simple humanoid (cylinder body + sphere head) — blue colored
  // Methods: switchLane(dir), takeDamage(amount), heal(amount), setWeapon(type)
  // update(dt): animate lane transition (ease-out cubic, same as CrowdRunner)
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 3: Bullet Entity + BulletManager

**Files:**
- Create: `src/entities/Bullet.ts`
- Create: `src/systems/BulletManager.ts`

Bullets travel forward (+Z) from the player. BulletManager pools them to avoid GC.

- [ ] **Step 1: Create Bullet class**

```typescript
class Bullet {
  // Small sphere/box mesh, position, velocity (0,0,+BULLET_SPEED), damage, active flag
  // update(dt): move forward, deactivate if past BULLET_DESPAWN_Z
  // activate(position, damage, spread): reset and fire from given position
  // deactivate(): hide mesh, mark inactive
}
```

- [ ] **Step 2: Create BulletManager**

```typescript
class BulletManager {
  // Pre-allocate pool of ~100 bullet instances
  // fireBullets(position, weaponConfig): get inactive bullets from pool, activate them
  //   - single bullet for pistol/smg/laser/rocket
  //   - 5 bullets with spread for shotgun
  // update(dt): update all active bullets, deactivate expired ones
  // getActiveBullets(): return active bullet list for collision checks
}
```

- [ ] **Step 3: Verify it compiles**
- [ ] **Step 4: Commit**

---

### Task 4: UIManager

**Files:**
- Create: `src/ui/UIManager.ts`

- [ ] **Step 1: Create UIManager**

```typescript
class UIManager {
  // Binds to all DOM elements from index.html
  // Methods: updateScore(n), updateDistance(n), updateHP(current, max),
  //   updateWeapon(name), showCombo(n), hideCombo(),
  //   showBossHP(name, current, max), hideBossHP(),
  //   showStartScreen(), hideStartScreen(), showGameOver(score, distance, kills),
  //   hideGameOver(), onStartGame(cb), onRestartGame(cb)
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 5: GameManager + main.ts — First Playable

**Files:**
- Create: `src/core/GameManager.ts`
- Create: `src/main.ts`

Wire everything together. Player stands on road, auto-fires bullets forward. Lane switching works. HP displays. No enemies yet.

- [ ] **Step 1: Create GameManager**

```typescript
class GameManager {
  // Singleton. Holds all systems + player.
  // initialize(canvas): create SceneManager, InputHandler, UIManager, Player, BulletManager
  // startGame(): reset state, start loop
  // gameLoop(): requestAnimationFrame, compute dt, call update(dt), try/catch
  // update(dt):
  //   1. Read input → player.switchLane
  //   2. player.update(dt)
  //   3. Auto-fire: track fireTimer, when ready call bulletManager.fireBullets(player.pos, weapon)
  //   4. bulletManager.update(dt)
  //   5. Update distance, score
  //   6. UIManager updates
  // gameOver(): stop loop, show screen
}
```

- [ ] **Step 2: Create main.ts**

```typescript
async function main() {
  const canvas = document.getElementById('renderCanvas') as HTMLCanvasElement;
  const game = GameManager.getInstance();
  await game.initialize(canvas);
}
```

- [ ] **Step 3: Run `npx vite` and verify**: player visible, lane switching works, bullets fire forward, HP bar shows
- [ ] **Step 4: Commit**

```
git commit -m "🏗️ feat: core game loop — player, shooting, lane switching"
```

---

## Chunk 2: Enemies + Collision

### Task 6: Enemy Entity

**Files:**
- Create: `src/entities/Enemy.ts`

- [ ] **Step 1: Create Enemy class**

```typescript
class Enemy {
  // Mesh: colored shape based on type (sphere for basic, box for armored, cone for fast, etc.)
  // State: type, hp, maxHp, position, lane, active, speed
  // HP bar: small plane above enemy showing remaining HP (only for hp > 1)
  // update(dt): move toward player (-Z), flankers randomly switch lanes
  // takeDamage(amount): reduce HP, flash red, return true if killed
  // activate(type, lane, z): reset for reuse from pool
  // deactivate(): hide, mark inactive
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 7: EnemyManager

**Files:**
- Create: `src/systems/EnemyManager.ts`

- [ ] **Step 1: Create EnemyManager**

```typescript
class EnemyManager {
  // Pool of ~30 enemy instances
  // Spawn timer: every ENEMY_SPAWN_INTERVAL, spawn 1-3 enemies
  // Wave difficulty: as distance increases, spawn more armored/fast/shielded types
  // spawnEnemy(type, lane): get from pool, activate
  // update(dt): move all active, deactivate if past despawn Z
  // getActiveEnemies(): for collision
  // clearAll(): deactivate everything (for restart)
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 8: CollisionSystem

**Files:**
- Create: `src/systems/CollisionSystem.ts`

- [ ] **Step 1: Create CollisionSystem**

Circle-based collision (distance < sum of radii). Checks each frame:

```typescript
class CollisionSystem {
  // checkBulletEnemyCollisions(bullets, enemies):
  //   For each active bullet × active enemy: if hit → enemy.takeDamage, bullet.deactivate
  //   Returns: { kills: Enemy[], hits: number }
  //
  // checkEnemyPlayerCollisions(enemies, player):
  //   For each active enemy: if reached player Z and same lane → player.takeDamage, enemy.deactivate
  //   Returns: { hits: number }
  //
  // checkBulletFrozenCollisions(bullets, frozenUpgrades):
  //   For each active bullet × active frozen: if hit → frozen.takeDamage, bullet.deactivate
  //   Returns: { thawed: FrozenUpgrade[] }
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 9: Wire Enemies into GameManager

**Files:**
- Modify: `src/core/GameManager.ts`

- [ ] **Step 1: Integrate EnemyManager + CollisionSystem into update loop**

```
update(dt):
  ... existing player + bullet logic ...
  5. enemyManager.update(dt)
  6. collisionSystem.checkBulletEnemyCollisions → on kill: score += enemy.score, show floating text
  7. collisionSystem.checkEnemyPlayerCollisions → on hit: player.takeDamage, shake camera
  8. Check game over: if player.hp <= 0 → gameOver()
```

- [ ] **Step 2: Run and verify**: enemies spawn, approach, get killed by bullets, damage player if they reach you
- [ ] **Step 3: Commit**

```
git commit -m "🏗️ feat: enemies spawn, take damage, kill player on contact"
```

---

## Chunk 3: Frozen Upgrades + Weapons

### Task 10: FrozenUpgrade Entity

**Files:**
- Create: `src/entities/FrozenUpgrade.ts`

- [ ] **Step 1: Create FrozenUpgrade class**

```typescript
class FrozenUpgrade {
  // Visual: translucent ice box with colored inner shape (the reward) visible inside
  // State: iceHP, maxIceHP, reward (WeaponType or 'heal'), position, lane, active
  // Ice HP bar above it (cyan colored)
  // update(dt): move toward player (slower than enemies — FROZEN_SPEED)
  // takeDamage(amount): reduce iceHP, crack effect, if iceHP <= 0 → thawed = true
  // When thawed: ice shatters (particle burst), inner reward becomes collectible
  // Player auto-collects when thawed and in same lane
}
```

- [ ] **Step 2: Verify it compiles**
- [ ] **Step 3: Commit**

---

### Task 11: FrozenUpgradeManager + Weapon Switching

**Files:**
- Create: `src/systems/FrozenUpgradeManager.ts`
- Modify: `src/core/GameManager.ts`

- [ ] **Step 1: Create FrozenUpgradeManager**

```typescript
class FrozenUpgradeManager {
  // Random spawn chance per frame (low — ~1 every 15-20 seconds)
  // Picks a random weapon upgrade (weighted: SMG common, rocket rare) or heal
  // Spawns in random lane
  // update(dt): move all active, remove if past despawn
  // getActiveUpgrades(): for collision
}
```

- [ ] **Step 2: Wire into GameManager**

```
update(dt):
  ... existing ...
  9. frozenUpgradeManager.update(dt)
  10. collisionSystem.checkBulletFrozenCollisions → on thaw: show reward
  11. If thawed upgrade in player's lane → player.setWeapon(reward), show floating text, play sound
```

- [ ] **Step 3: Run and verify**: ice blocks appear, shooting them cracks them, thawed blocks give weapons, weapon changes fire rate/spread
- [ ] **Step 4: Commit**

```
git commit -m "🏗️ feat: frozen upgrades — shoot ice to unlock weapons"
```

---

## Chunk 4: Juice — Sound, Particles, Camera, Floating Text

### Task 12: SoundSystem

**Files:**
- Create: `src/systems/SoundSystem.ts`

- [ ] **Step 1: Port SoundSystem from CrowdRunner, add new sounds:**

```
Sounds needed:
- SHOOT: short click/pop (per weapon type — pistol pop, smg rattle, shotgun boom, laser zap, rocket whoosh)
- ENEMY_HIT: thud
- ENEMY_KILL: satisfying crunch
- PLAYER_HIT: warning buzz
- ICE_CRACK: glass crack
- ICE_SHATTER: glass break + sparkle
- WEAPON_PICKUP: ascending power chord
- BOSS_INTRO: deep horn
- BOSS_DEATH: explosion
```

- [ ] **Step 2: Commit**

---

### Task 13: ParticleSystem

**Files:**
- Create: `src/systems/ParticleSystem.ts`

- [ ] **Step 1: Port ParticleSystem from CrowdRunner, add new effects:**

```
Effects needed:
- Muzzle flash (small yellow burst at player position)
- Enemy hit spark (small red burst at impact)
- Enemy death explosion (larger burst matching enemy color)
- Ice crack particles (cyan shards)
- Ice shatter (big cyan burst)
- Weapon pickup celebration (colored burst)
- Boss explosion (massive multi-color)
```

- [ ] **Step 2: Commit**

---

### Task 14: CameraEffects + FloatingText

**Files:**
- Create: `src/systems/CameraEffects.ts`
- Create: `src/systems/FloatingText.ts`

- [ ] **Step 1: Port CameraEffects from CrowdRunner as-is**
- [ ] **Step 2: Port FloatingText from CrowdRunner as-is** (already has proper Vector3 + renderingGroupId fixes)
- [ ] **Step 3: Wire all juice into GameManager** — sounds on shoot/hit/kill/pickup, particles on impacts, shake on damage, floating damage numbers
- [ ] **Step 4: Run and verify**: game feels punchy — every shot, hit, kill, and pickup has audio + visual feedback
- [ ] **Step 5: Commit**

```
git commit -m "🏗️ feat: juice — sound, particles, camera shake, damage numbers"
```

---

## Chunk 5: Boss System

### Task 15: Boss Entity + Integration

**Files:**
- Create: `src/entities/Boss.ts`
- Modify: `src/core/GameManager.ts`

- [ ] **Step 1: Create Boss class**

```typescript
class Boss {
  // Large mesh (3x enemy size), fills center of road
  // State: hp, maxHp, phase (1-3), active, attackTimer
  // HP bar shown in UI (top of screen)
  // Moves slowly toward player, stops at z=30 (stays at distance)
  // Attack patterns per phase:
  //   Phase 1: fires projectiles in player's lane (dodge to avoid)
  //   Phase 2: fires spread (2 lanes) — must find the safe lane
  //   Phase 3: rapid fire single lane, switching targets
  // takeDamage(amount): reduce HP, flash, check phase transitions
  // On death: explosion, drop guaranteed weapon upgrade
}
```

- [ ] **Step 2: Wire Boss into GameManager**

```
Every BOSS_INTERVAL_DISTANCE meters:
  1. Stop spawning normal enemies
  2. Show "WARNING" text + boss intro sound
  3. Spawn boss, show boss HP bar
  4. Boss fight until killed
  5. Drop reward, resume normal spawning
  6. Next boss has more HP
```

- [ ] **Step 3: Add boss projectile collision** — CollisionSystem checks boss projectiles → player
- [ ] **Step 4: Run and verify**: boss appears every 500m, has visible HP bar, takes many shots, drops upgrade on death
- [ ] **Step 5: Commit**

```
git commit -m "🏗️ feat: boss system — periodic boss fights with attack patterns"
```

---

## Chunk 6: Polish + Progression

### Task 16: Combo System + Score

- [ ] **Step 1: Track consecutive kills without taking damage**
- [ ] **Step 2: Show combo multiplier in UI, multiply score by combo**
- [ ] **Step 3: Commit**

### Task 17: Difficulty Scaling

- [ ] **Step 1: As distance increases**: more enemies per spawn, faster spawn rate, more armored/fast types, enemies move faster
- [ ] **Step 2: Commit**

### Task 18: Final Pass + Git Push

- [ ] **Step 1: Playtest end-to-end, fix any remaining issues**
- [ ] **Step 2: Init git repo, commit all, push**

```bash
cd /c/Personal/GunRunner
git init
git add -A
git commit -m "🏗️ feat: GunRunner — lane-based auto-shooter with frozen upgrades and bosses"
```

---

## Dependency Graph

```
Chunk 1 (core loop)
  Task 1: InputHandler
  Task 2: Player
  Task 3: Bullet + BulletManager
  Task 4: UIManager
  Task 5: GameManager + main.ts  ← depends on 1-4

Chunk 2 (enemies)
  Task 6: Enemy
  Task 7: EnemyManager
  Task 8: CollisionSystem
  Task 9: Wire into GameManager  ← depends on 5-8

Chunk 3 (upgrades)
  Task 10: FrozenUpgrade
  Task 11: FrozenUpgradeManager + wire  ← depends on 9-10

Chunk 4 (juice)
  Task 12: SoundSystem
  Task 13: ParticleSystem
  Task 14: CameraEffects + FloatingText + wire  ← depends on 9

Chunk 5 (boss)
  Task 15: Boss + wire  ← depends on 9

Chunk 6 (polish)
  Tasks 16-18  ← depends on all above
```

Chunks 3, 4, 5 are independent of each other and can be parallelized after Chunk 2.
