import { Scene } from '@babylonjs/core';
import { Enemy } from '@/entities/Enemy';
import { Config, EnemyType, Lane } from '@/core/Config';

const POOL_SIZE = 30;

export class EnemyManager {
  private pool: Enemy[] = [];
  private spawnTimer: number = 0;
  private spawnInterval: number = Config.ENEMY_SPAWN_INTERVAL;
  private distance: number = 0;
  private manualOverride: boolean = false;

  constructor(scene: Scene) {
    for (let i = 0; i < POOL_SIZE; i++) {
      this.pool.push(new Enemy(scene));
    }
  }

  public update(dt: number, currentDistance: number): void {
    this.distance = currentDistance;

    // Spawn timer
    this.spawnTimer += dt;
    if (this.spawnTimer >= this.spawnInterval) {
      this.spawnWave();
      this.spawnTimer = 0;
    }

    // Update all active
    for (const e of this.pool) {
      if (e.active) e.update(dt);
    }
  }

  private spawnWave(): void {
    // How many enemies per wave increases with distance
    const waveSize = Math.min(3, 1 + Math.floor(this.distance / 300));

    // Pick lanes — avoid stacking too many in one lane
    const usedLanes = new Set<Lane>();

    for (let i = 0; i < waveSize; i++) {
      const enemy = this.getInactive();
      if (!enemy) return;

      // Pick a lane not already used this wave
      const lanes = [Lane.LEFT, Lane.CENTER, Lane.RIGHT].filter(l => !usedLanes.has(l));
      if (lanes.length === 0) break;
      const lane = lanes[Math.floor(Math.random() * lanes.length)];
      usedLanes.add(lane);

      const type = this.rollEnemyType();
      const z = Config.ENEMY_SPAWN_DISTANCE + Math.random() * 10;
      enemy.activate(type, lane, z);
    }

    // Difficulty scaling — only if user hasn't overridden
    if (!this.manualOverride) {
      this.spawnInterval = Math.max(0.8, Config.ENEMY_SPAWN_INTERVAL - this.distance * 0.001);
    }
  }

  private rollEnemyType(): EnemyType {
    const r = Math.random();
    const d = this.distance;

    // Early game: mostly basic
    if (d < 150) return EnemyType.BASIC;

    // Mid game: introduce fast + armored
    if (d < 400) {
      if (r < 0.55) return EnemyType.BASIC;
      if (r < 0.75) return EnemyType.FAST;
      if (r < 0.90) return EnemyType.ARMORED;
      return EnemyType.SHIELDED;
    }

    // Late game: full mix
    if (r < 0.35) return EnemyType.BASIC;
    if (r < 0.55) return EnemyType.FAST;
    if (r < 0.75) return EnemyType.ARMORED;
    return EnemyType.SHIELDED;
  }

  public getActiveEnemies(): Enemy[] {
    return this.pool.filter(e => e.active);
  }

  public clearAll(): void {
    for (const e of this.pool) e.deactivate();
    this.spawnTimer = 0;
    this.spawnInterval = Config.ENEMY_SPAWN_INTERVAL;
  }

  /** Set spawn interval manually (from settings slider) */
  public setSpawnInterval(interval: number): void {
    this.spawnInterval = interval;
    this.manualOverride = true;
  }

  /** Pause spawning (for boss fights) */
  public pauseSpawning(): void { this.spawnInterval = Infinity; }

  /** Resume spawning */
  public resumeSpawning(): void {
    this.spawnInterval = Math.max(0.8, Config.ENEMY_SPAWN_INTERVAL - this.distance * 0.001);
  }

  private getInactive(): Enemy | null {
    for (const e of this.pool) {
      if (!e.active) return e;
    }
    return null;
  }
}
