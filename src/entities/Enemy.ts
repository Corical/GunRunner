import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh,
} from '@babylonjs/core';
import { Config, EnemyType, ENEMIES, EnemyConfig, Lane } from '@/core/Config';

export class Enemy {
  public active: boolean = false;
  public position: Vector3;
  public lane: Lane = Lane.CENTER;
  public type: EnemyType = EnemyType.BASIC;
  public hp: number = 1;
  public maxHp: number = 1;
  public config!: EnemyConfig;

  private mesh: Mesh;
  private hpBarBg: Mesh | null = null;
  private hpBarFill: Mesh | null = null;
  private scene: Scene;
  private mat: StandardMaterial;
  private flashTimer: number = 0;
  private laneSwitchTimer: number = 0;

  constructor(scene: Scene) {
    this.scene = scene;
    this.position = Vector3.Zero();

    // Default mesh — will be resized on activate
    this.mesh = MeshBuilder.CreateBox('enemy', { size: 1 }, scene);
    this.mat = new StandardMaterial('enemyMat', scene);
    this.mat.diffuseColor = Color3.Red();
    this.mat.emissiveColor = Color3.Red().scale(0.3);
    this.mesh.material = this.mat;
    this.mesh.isPickable = false;
    this.mesh.setEnabled(false);
  }

  public activate(type: EnemyType, lane: Lane, z: number): void {
    this.active = true;
    this.type = type;
    this.config = ENEMIES[type];
    this.hp = this.config.hp;
    this.maxHp = this.config.hp;
    this.lane = lane;

    const laneX = lane === Lane.LEFT ? Config.LANES.LEFT
      : lane === Lane.RIGHT ? Config.LANES.RIGHT : Config.LANES.CENTER;
    this.position.set(laneX, this.config.size * 0.5, z);

    // Resize and color
    const s = this.config.size;
    this.mesh.scaling.set(s, s, s);
    const color = Color3.FromHexString(this.config.color);
    this.mat.diffuseColor = color;
    this.mat.emissiveColor = color.scale(0.3);

    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);

    // HP bar for multi-hp enemies
    if (this.maxHp > 1) {
      this.createHPBar();
    }

    this.laneSwitchTimer = 2 + Math.random() * 3;
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
    if (this.hpBarBg) { this.hpBarBg.setEnabled(false); }
    if (this.hpBarFill) { this.hpBarFill.setEnabled(false); }
  }

  public update(dt: number): void {
    if (!this.active) return;

    // Move toward player
    this.position.z -= Config.ENEMY_SPEED * this.config.speed * dt;
    this.mesh.position.copyFrom(this.position);

    // Flankers switch lanes
    if (this.config.switchesLanes) {
      this.laneSwitchTimer -= dt;
      if (this.laneSwitchTimer <= 0) {
        this.laneSwitchTimer = 1.5 + Math.random() * 2;
        const lanes = [Lane.LEFT, Lane.CENTER, Lane.RIGHT];
        const otherLanes = lanes.filter(l => l !== this.lane);
        this.lane = otherLanes[Math.floor(Math.random() * otherLanes.length)];
        const targetX = this.lane === Lane.LEFT ? Config.LANES.LEFT
          : this.lane === Lane.RIGHT ? Config.LANES.RIGHT : Config.LANES.CENTER;
        this.position.x = targetX; // snap for now
      }
    }

    // Flash decay
    if (this.flashTimer > 0) {
      this.flashTimer -= dt;
      if (this.flashTimer <= 0) {
        const color = Color3.FromHexString(this.config.color);
        this.mat.emissiveColor = color.scale(0.3);
      }
    }

    // Update HP bar
    if (this.hpBarFill && this.hpBarBg) {
      this.hpBarBg.position.set(this.position.x, this.config.size + 0.5, this.position.z);
      this.hpBarFill.position.set(this.position.x, this.config.size + 0.5, this.position.z);
      this.hpBarFill.scaling.x = Math.max(0, this.hp / this.maxHp);
    }

    // Despawn if past player
    if (this.position.z < Config.ENEMY_DESPAWN_Z) {
      this.deactivate();
    }
  }

  /** Returns true if enemy is killed */
  public takeDamage(amount: number): boolean {
    this.hp -= amount;
    this.flashTimer = 0.1;
    this.mat.emissiveColor = new Color3(1, 1, 1);

    if (this.hp <= 0) {
      this.deactivate();
      return true;
    }
    return false;
  }

  public getCollisionRadius(): number {
    return this.config.size * 0.6;
  }

  private createHPBar(): void {
    if (!this.hpBarBg) {
      this.hpBarBg = MeshBuilder.CreatePlane('ehpBg', { width: 1.5, height: 0.15 }, this.scene);
      const bgMat = new StandardMaterial('ehpBgMat', this.scene);
      bgMat.diffuseColor = new Color3(0.2, 0.2, 0.2);
      bgMat.emissiveColor = new Color3(0.1, 0.1, 0.1);
      bgMat.backFaceCulling = false;
      this.hpBarBg.material = bgMat;
      this.hpBarBg.billboardMode = Mesh.BILLBOARDMODE_ALL;
      this.hpBarBg.renderingGroupId = 1;
      this.hpBarBg.isPickable = false;
    }

    if (!this.hpBarFill) {
      this.hpBarFill = MeshBuilder.CreatePlane('ehpFill', { width: 1.4, height: 0.1 }, this.scene);
      const fillMat = new StandardMaterial('ehpFillMat', this.scene);
      fillMat.diffuseColor = Color3.Red();
      fillMat.emissiveColor = Color3.Red().scale(0.5);
      fillMat.backFaceCulling = false;
      this.hpBarFill.material = fillMat;
      this.hpBarFill.billboardMode = Mesh.BILLBOARDMODE_ALL;
      this.hpBarFill.renderingGroupId = 1;
      this.hpBarFill.isPickable = false;
    }

    this.hpBarBg.setEnabled(true);
    this.hpBarFill.setEnabled(true);
    this.hpBarFill.scaling.x = 1;
  }
}
