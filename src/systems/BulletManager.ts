import { Scene, Vector3 } from '@babylonjs/core';
import { Bullet } from '@/entities/Bullet';
import { WeaponConfig } from '@/core/Config';

const POOL_SIZE = 120;

export class BulletManager {
  private pool: Bullet[] = [];

  constructor(scene: Scene) {
    for (let i = 0; i < POOL_SIZE; i++) {
      this.pool.push(new Bullet(scene));
    }
  }

  /** Fire bullets from a position using the weapon config */
  public fire(muzzlePos: Vector3, weapon: WeaponConfig): void {
    for (let i = 0; i < weapon.bulletCount; i++) {
      const bullet = this.getInactive();
      if (!bullet) return; // pool exhausted

      // Calculate spread for multi-bullet weapons (shotgun)
      let spreadX = 0;
      if (weapon.bulletCount > 1) {
        const t = weapon.bulletCount === 1 ? 0 : (i / (weapon.bulletCount - 1)) - 0.5;
        spreadX = t * weapon.bulletSpread;
      }

      bullet.activate(muzzlePos.clone(), weapon.damage, spreadX);
    }
  }

  public update(dt: number): void {
    for (const b of this.pool) {
      if (b.active) b.update(dt);
    }
  }

  public getActiveBullets(): Bullet[] {
    return this.pool.filter(b => b.active);
  }

  public clearAll(): void {
    for (const b of this.pool) b.deactivate();
  }

  private getInactive(): Bullet | null {
    for (const b of this.pool) {
      if (!b.active) return b;
    }
    return null;
  }
}
