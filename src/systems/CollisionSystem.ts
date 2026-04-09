import { Bullet } from '@/entities/Bullet';
import { Enemy } from '@/entities/Enemy';
import { Player } from '@/entities/Player';
import { Config } from '@/core/Config';

export interface KillEvent {
  enemy: Enemy;
  position: { x: number; y: number; z: number };
}

export interface HitEvent {
  position: { x: number; y: number; z: number };
  damage: number;
}

export interface CollisionResult {
  kills: KillEvent[];
  enemyHits: HitEvent[];
  playerHits: number;
  frozenHits: number[];
}

export class CollisionSystem {

  /** Check bullets hitting enemies. Deactivates bullets on hit. */
  public checkBulletEnemyCollisions(bullets: Bullet[], enemies: Enemy[]): { kills: KillEvent[]; hits: HitEvent[] } {
    const kills: KillEvent[] = [];
    const hits: HitEvent[] = [];

    // Track which enemies were already hit by each bullet (for penetration)
    const bulletHitSet = new Set<string>();

    for (const bullet of bullets) {
      if (!bullet.active) continue;

      for (const enemy of enemies) {
        if (!enemy.active) continue;

        const dx = bullet.position.x - enemy.position.x;
        const dz = bullet.position.z - enemy.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (dist < Config.BULLET_HIT_RADIUS + enemy.getCollisionRadius()) {
          // Prevent same bullet hitting same enemy twice
          const key = `${bullets.indexOf(bullet)}_${enemies.indexOf(enemy)}`;
          if (bulletHitSet.has(key)) continue;
          bulletHitSet.add(key);

          const killed = enemy.takeDamage(bullet.damage);
          const pos = { x: enemy.position.x, y: enemy.position.y, z: enemy.position.z };

          if (killed) {
            kills.push({ enemy, position: pos });
          } else {
            hits.push({ position: pos, damage: bullet.damage });
          }

          // Splash damage — hit nearby enemies too
          if (bullet.splashRadius > 0) {
            for (const other of enemies) {
              if (!other.active || other === enemy) continue;
              const sdx = enemy.position.x - other.position.x;
              const sdz = enemy.position.z - other.position.z;
              const sDist = Math.sqrt(sdx * sdx + sdz * sdz);
              if (sDist < bullet.splashRadius) {
                const splashKilled = other.takeDamage(Math.max(1, Math.floor(bullet.damage / 2)));
                const sPos = { x: other.position.x, y: other.position.y, z: other.position.z };
                if (splashKilled) {
                  kills.push({ enemy: other, position: sPos });
                } else {
                  hits.push({ position: sPos, damage: 1 });
                }
              }
            }
          }

          // Penetration — bullet continues through if it has charges left
          const shouldDeactivate = bullet.onHit();
          if (shouldDeactivate) break; // bullet spent, stop checking enemies
          // else: bullet keeps going, check next enemy
        }
      }
    }

    return { kills, hits };
  }

  /** Check if enemies have reached the player */
  public checkEnemyPlayerCollisions(enemies: Enemy[], player: Player): number {
    let hitCount = 0;
    const playerPos = player.getPosition();

    for (const enemy of enemies) {
      if (!enemy.active) continue;

      // Enemy reached player's z-line and is in the same lane
      if (enemy.position.z <= playerPos.z + Config.ENEMY_HIT_PLAYER_RADIUS) {
        const dx = Math.abs(enemy.position.x - playerPos.x);
        if (dx < Config.ENEMY_HIT_PLAYER_RADIUS + enemy.getCollisionRadius()) {
          player.takeDamage(1);
          enemy.deactivate();
          hitCount++;
        }
      }
    }

    return hitCount;
  }

  /** Check bullets hitting frozen upgrades. Returns indices of hit upgrades + damage dealt. */
  public checkBulletFrozenCollisions(
    bullets: Bullet[],
    frozenPositions: { x: number; z: number; radius: number; active: boolean }[],
    onHit: (index: number, damage: number) => void
  ): void {
    for (const bullet of bullets) {
      if (!bullet.active) continue;

      for (let i = 0; i < frozenPositions.length; i++) {
        const frozen = frozenPositions[i];
        if (!frozen.active) continue;

        const dx = bullet.position.x - frozen.x;
        const dz = bullet.position.z - frozen.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (dist < Config.BULLET_HIT_RADIUS + frozen.radius) {
          onHit(i, bullet.damage);
          bullet.deactivate();
          break;
        }
      }
    }
  }
}
