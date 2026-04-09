import { Scene } from '@babylonjs/core';
import { FrozenUpgrade, FrozenReward } from '@/entities/FrozenUpgrade';
import { Config, WeaponType, Lane } from '@/core/Config';

const POOL_SIZE = 5;

// Weighted reward table — cumulative thresholds must sum to 1.0
const REWARD_WEIGHTS: { reward: FrozenReward; threshold: number }[] = [
  { reward: WeaponType.SMG,     threshold: 0.30 },
  { reward: WeaponType.SHOTGUN, threshold: 0.55 },
  { reward: WeaponType.LASER,   threshold: 0.75 },
  { reward: 'heal',             threshold: 0.90 },
  { reward: WeaponType.ROCKET,  threshold: 1.00 },
];

const ALL_LANES = [Lane.LEFT, Lane.CENTER, Lane.RIGHT] as const;

function rollReward(): FrozenReward {
  const r = Math.random();
  for (const entry of REWARD_WEIGHTS) {
    if (r < entry.threshold) return entry.reward;
  }
  return WeaponType.SMG;
}

function pickRandomLane(): Lane {
  return ALL_LANES[Math.floor(Math.random() * ALL_LANES.length)];
}

export class FrozenUpgradeManager {
  private pool: FrozenUpgrade[] = [];

  constructor(scene: Scene) {
    for (let i = 0; i < POOL_SIZE; i++) {
      this.pool.push(new FrozenUpgrade(scene));
    }
  }

  public spawnUpgrade(reward?: FrozenReward): void {
    const upgrade = this.getInactive();
    if (!upgrade) return;

    const selectedReward = reward ?? rollReward();
    const lane = pickRandomLane();
    const z = Config.ENEMY_SPAWN_DISTANCE + Math.random() * 10;

    upgrade.activate(selectedReward, lane, z);
  }

  public update(dt: number): void {
    for (const upgrade of this.pool) {
      if (upgrade.active) upgrade.update(dt);
    }
  }

  public getActiveUpgrades(): FrozenUpgrade[] {
    return this.pool.filter(u => u.active);
  }

  public clearAll(): void {
    for (const upgrade of this.pool) {
      upgrade.deactivate();
    }
  }

  private getInactive(): FrozenUpgrade | null {
    for (const upgrade of this.pool) {
      if (!upgrade.active) return upgrade;
    }
    return null;
  }
}
