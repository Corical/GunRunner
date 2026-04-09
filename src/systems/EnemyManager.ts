import { Scene } from '@babylonjs/core';
import { Enemy } from '@/entities/Enemy';
import { Config, EnemyType } from '@/core/Config';

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
    const waveSize = Math.min(3, 1 + Math.floor(this.distance / 300));
    const roadHalf = Config.ROAD_WIDTH / 2 - 1;

    // Spread enemies across the road width, avoid stacking
    const usedXZones: number[] = [];

    for (let i = 0; i < waveSize; i++) {
      const enemy = this.getInactive();
      if (!enemy) return;

      // Pick a random X position, avoiding overlap with others in this wave
      let xPos: number;
      let attempts = 0;
      do {
        xPos = (Math.random() - 0.5) * 2 * roadHalf;
        attempts++;
      } while (attempts < 10 && usedXZones.some(x => Math.abs(x - xPos) < 2.5));
      usedXZones.push(xPos);

      const type = this.rollEnemyType();
      const z = Config.ENEMY_SPAWN_DISTANCE + Math.random() * 10;
      enemy.activate(type, xPos, z);
    }

    // Difficulty scaling — only if user hasn't overridden
    if (!this.manualOverride) {
      this.spawnInterval = Math.max(0.8, Config.ENEMY_SPAWN_INTERVAL - this.distance * 0.001);
    }
  }

  private rollEnemyType(): EnemyType {
    const r = Math.random();
    const d = this.distance;

    // Early game (0-150m): mostly basic, a few fast
    if (d < 150) {
      return r < 0.85 ? EnemyType.BASIC : EnemyType.FAST;
    }

    // Mid game (150-400m): introduce armored, shielded, bomber
    if (d < 400) {
      if (r < 0.40) return EnemyType.BASIC;
      if (r < 0.55) return EnemyType.FAST;
      if (r < 0.70) return EnemyType.ARMORED;
      if (r < 0.80) return EnemyType.SHIELDED;
      if (r < 0.90) return EnemyType.BOMBER;
      return EnemyType.HEALER;
    }

    // Late game (400-800m): full mix, more heavies
    if (d < 800) {
      if (r < 0.25) return EnemyType.BASIC;
      if (r < 0.40) return EnemyType.FAST;
      if (r < 0.55) return EnemyType.ARMORED;
      if (r < 0.65) return EnemyType.SHIELDED;
      if (r < 0.75) return EnemyType.BOMBER;
      if (r < 0.85) return EnemyType.HEALER;
      return EnemyType.SPLITTER;
    }

    // Endgame (800m+): everything, weighted toward dangerous types
    if (r < 0.15) return EnemyType.BASIC;
    if (r < 0.25) return EnemyType.FAST;
    if (r < 0.40) return EnemyType.ARMORED;
    if (r < 0.50) return EnemyType.SHIELDED;
    if (r < 0.65) return EnemyType.BOMBER;
    if (r < 0.80) return EnemyType.HEALER;
    return EnemyType.SPLITTER;
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
