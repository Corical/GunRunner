import { Scene } from '@babylonjs/core';
import { Tower } from '@/entities/Tower';
import { TowerType } from '@/core/Config';
import { Enemy } from '@/entities/Enemy';

const POOL_SIZE = 6;

export class TowerManager {
  private pool: Tower[] = [];

  constructor(scene: Scene) {
    for (let i = 0; i < POOL_SIZE; i++) {
      this.pool.push(new Tower(scene));
    }
  }

  /** Deploy a tower at the given X position */
  public deploy(type: TowerType, xPos: number): void {
    const tower = this.getInactive();
    if (!tower) return;
    tower.activate(type, xPos);
  }

  public update(dt: number, enemies: Enemy[]): void {
    for (const tower of this.pool) {
      if (!tower.active) continue;
      tower.update(dt);
      tower.applyEffects(enemies);
    }
  }

  public clearAll(): void {
    for (const tower of this.pool) tower.deactivate();
  }

  private getInactive(): Tower | null {
    for (const tower of this.pool) {
      if (!tower.active) return tower;
    }
    return null;
  }
}
