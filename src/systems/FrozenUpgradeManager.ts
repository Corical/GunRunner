import { Scene } from '@babylonjs/core';
import { FrozenUpgrade, FrozenReward } from '@/entities/FrozenUpgrade';
import { Config, WeaponType, TowerType } from '@/core/Config';

const POOL_SIZE = 5;

// Weighted reward table — cumulative thresholds must sum to 1.0
const REWARD_WEIGHTS: { reward: FrozenReward; threshold: number }[] = [
  { reward: WeaponType.SMG,           threshold: 0.08 },
  { reward: WeaponType.SHOTGUN,       threshold: 0.16 },
  { reward: WeaponType.LASER,         threshold: 0.24 },
  { reward: WeaponType.MINIGUN,       threshold: 0.30 },
  { reward: WeaponType.FLAMETHROWER,  threshold: 0.36 },
  { reward: WeaponType.GRENADE,       threshold: 0.42 },
  { reward: 'heal',                   threshold: 0.50 },
  { reward: 'armor',                  threshold: 0.56 },
  { reward: 'maxhp',                  threshold: 0.62 },
  { reward: 'frenzy',                 threshold: 0.68 },
  { reward: 'speed',                  threshold: 0.74 },
  { reward: TowerType.FREEZE,         threshold: 0.80 },
  { reward: TowerType.FIRE,           threshold: 0.86 },
  { reward: TowerType.POISON,         threshold: 0.92 },
  { reward: WeaponType.ROCKET,        threshold: 0.96 },
  { reward: WeaponType.RAILGUN,       threshold: 1.00 },
];

function rollReward(): FrozenReward {
  const r = Math.random();
  for (const entry of REWARD_WEIGHTS) {
    if (r < entry.threshold) return entry.reward;
  }
  return WeaponType.SMG;
}

function randomX(): number {
  const roadHalf = Config.ROAD_WIDTH / 2 - 1;
  return (Math.random() - 0.5) * 2 * roadHalf;
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
    const xPos = randomX();
    const z = Config.ENEMY_SPAWN_DISTANCE + Math.random() * 10;

    upgrade.activate(selectedReward, xPos, z);
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
