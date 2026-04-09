import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, TransformNode, Mesh,
} from '@babylonjs/core';
import { Config, WeaponType, WEAPONS, WeaponConfig } from '@/core/Config';
import { WeaponModelBuilder } from '@/utils/WeaponModelBuilder';

const MOVE_SPEED = 15; // Units per second lateral movement
const ROAD_HALF = Config.ROAD_WIDTH / 2 - 0.5; // Stay slightly inside road edges

export class Player {
  private position: Vector3;

  private hp: number;
  private maxHp: number;
  private weapon: WeaponType = WeaponType.PISTOL;
  private fireTimer: number = 0;

  // Buffs
  private armor: number = 0;
  private frenzyTimer: number = 0;
  private speedBoostTimer: number = 0;

  private mesh: TransformNode;
  private gunMesh: Mesh | null = null;
  private scene: Scene;

  // Damage flash
  private flashTimer: number = 0;
  private bodyMat: StandardMaterial;

  constructor(scene: Scene) {
    this.scene = scene;
    this.hp = Config.INITIAL_HP;
    this.maxHp = Config.INITIAL_HP;
    this.position = new Vector3(0, Config.PLAYER_HEIGHT, Config.PLAYER_Z_POSITION);

    this.mesh = new TransformNode('player', scene);

    const color = Color3.FromHexString(Config.COLORS.PLAYER);
    this.bodyMat = new StandardMaterial('playerMat', scene);
    this.bodyMat.diffuseColor = color;
    this.bodyMat.emissiveColor = color.scale(0.2);

    const body = MeshBuilder.CreateCylinder('pBody', { diameter: 0.7, height: 1.2, tessellation: 8 }, scene);
    body.position.y = 0.6;
    body.material = this.bodyMat;
    body.parent = this.mesh;

    const head = MeshBuilder.CreateSphere('pHead', { diameter: 0.5, segments: 8 }, scene);
    head.position.y = 1.5;
    head.material = this.bodyMat;
    head.parent = this.mesh;

    this.equipWeaponModel(WeaponType.PISTOL);
    this.mesh.position = this.position;
  }

  /** Move player laterally. direction: -1 (left), 0 (stop), 1 (right) */
  public move(direction: number, dt: number): void {
    if (direction === 0) return;
    this.position.x += direction * MOVE_SPEED * dt;
    // Clamp to road edges
    this.position.x = Math.max(-ROAD_HALF, Math.min(ROAD_HALF, this.position.x));
  }

  public update(dt: number): void {
    this.mesh.position.copyFrom(this.position);

    if (this.flashTimer > 0) {
      this.flashTimer -= dt;
      if (this.flashTimer <= 0) {
        this.bodyMat.emissiveColor = Color3.FromHexString(Config.COLORS.PLAYER).scale(0.2);
      }
    }

    this.fireTimer += dt;
    if (this.frenzyTimer > 0) this.frenzyTimer -= dt;
    if (this.speedBoostTimer > 0) this.speedBoostTimer -= dt;
  }

  public tryFire(): boolean {
    const weapon = this.getWeaponConfig();
    let rate = weapon.fireRate;
    if (this.speedBoostTimer > 0) rate *= 1.5;
    const interval = 1 / rate;
    if (this.fireTimer >= interval) {
      this.fireTimer = 0;
      return true;
    }
    return false;
  }

  public getDamageMultiplier(): number {
    return this.frenzyTimer > 0 ? 2 : 1;
  }

  public takeDamage(amount: number): void {
    if (this.armor > 0) {
      const absorbed = Math.min(this.armor, amount);
      this.armor -= absorbed;
      amount -= absorbed;
    }
    if (amount > 0) {
      this.hp = Math.max(0, this.hp - amount);
    }
    this.flashTimer = 0.2;
    this.bodyMat.emissiveColor = new Color3(1, 0.2, 0.2);
  }

  public heal(amount: number): void { this.hp = Math.min(this.maxHp, this.hp + amount); }
  public addArmor(amount: number): void { this.armor += amount; }
  public addMaxHP(amount: number): void {
    this.maxHp = Math.min(Config.MAX_HP, this.maxHp + amount);
    this.hp = Math.min(this.maxHp, this.hp + amount);
  }
  public activateFrenzy(duration: number): void { this.frenzyTimer = duration; }
  public activateSpeedBoost(duration: number): void { this.speedBoostTimer = duration; }
  public hasFrenzy(): boolean { return this.frenzyTimer > 0; }
  public hasSpeedBoost(): boolean { return this.speedBoostTimer > 0; }
  public getArmor(): number { return this.armor; }

  public setWeapon(type: WeaponType): void {
    this.weapon = type;
    this.fireTimer = 0;
    this.equipWeaponModel(type);
  }

  private equipWeaponModel(type: WeaponType): void {
    if (this.gunMesh) { this.gunMesh.dispose(); this.gunMesh = null; }
    this.gunMesh = WeaponModelBuilder.create(this.scene, type);
    this.gunMesh.scaling.setAll(2.5);
    this.gunMesh.position.set(0.5, 0.9, 0.8);
    this.gunMesh.parent = this.mesh;
  }

  public getWeaponConfig(): WeaponConfig { return WEAPONS[this.weapon]; }
  public getWeaponType(): WeaponType { return this.weapon; }
  public getHP(): number { return this.hp; }
  public getMaxHP(): number { return this.maxHp; }
  public isAlive(): boolean { return this.hp > 0; }
  public getPosition(): Vector3 { return this.position.clone(); }
  public getX(): number { return this.position.x; }
  public getMuzzlePosition(): Vector3 { return new Vector3(this.position.x, 1, this.position.z + 1); }

  public reset(): void {
    this.hp = Config.INITIAL_HP;
    this.maxHp = Config.INITIAL_HP;
    this.weapon = WeaponType.PISTOL;
    this.fireTimer = 0;
    this.armor = 0;
    this.frenzyTimer = 0;
    this.speedBoostTimer = 0;
    this.equipWeaponModel(WeaponType.PISTOL);
    this.position.set(0, Config.PLAYER_HEIGHT, Config.PLAYER_Z_POSITION);
    this.mesh.position.copyFrom(this.position);
  }
}
