import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, TransformNode, Mesh,
} from '@babylonjs/core';
import { Config, Lane, LaneDirection, WeaponType, WEAPONS, WeaponConfig } from '@/core/Config';
import { WeaponModelBuilder } from '@/utils/WeaponModelBuilder';

export class Player {
  private position: Vector3;
  private currentLane: Lane = Lane.CENTER;
  private targetLane: Lane = Lane.CENTER;
  private laneProgress: number = 1;
  private laneStartX: number = 0;
  private laneTargetX: number = 0;

  private hp: number;
  private maxHp: number;
  private weapon: WeaponType = WeaponType.PISTOL;
  private fireTimer: number = 0;

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
    this.position = new Vector3(Config.LANES.CENTER, Config.PLAYER_HEIGHT, Config.PLAYER_Z_POSITION);

    // Build player mesh — simple humanoid
    this.mesh = new TransformNode('player', scene);

    const color = Color3.FromHexString(Config.COLORS.PLAYER);
    this.bodyMat = new StandardMaterial('playerMat', scene);
    this.bodyMat.diffuseColor = color;
    this.bodyMat.emissiveColor = color.scale(0.2);

    // Body
    const body = MeshBuilder.CreateCylinder('pBody', { diameter: 0.7, height: 1.2, tessellation: 8 }, scene);
    body.position.y = 0.6;
    body.material = this.bodyMat;
    body.parent = this.mesh;

    // Head
    const head = MeshBuilder.CreateSphere('pHead', { diameter: 0.5, segments: 8 }, scene);
    head.position.y = 1.5;
    head.material = this.bodyMat;
    head.parent = this.mesh;

    // Weapon model
    this.equipWeaponModel(WeaponType.PISTOL);

    this.mesh.position = this.position;
  }

  public switchLane(direction: LaneDirection): void {
    if (direction === LaneDirection.NONE || this.laneProgress < 1) return;
    const newLane = this.currentLane + direction;
    if (newLane < Lane.LEFT || newLane > Lane.RIGHT) return;

    this.targetLane = newLane as Lane;
    this.laneProgress = 0;
    this.laneStartX = this.position.x;
    this.laneTargetX = this.getLaneX(this.targetLane);
  }

  private getLaneX(lane: Lane): number {
    return lane === Lane.LEFT ? Config.LANES.LEFT
      : lane === Lane.RIGHT ? Config.LANES.RIGHT
      : Config.LANES.CENTER;
  }

  public update(dt: number): void {
    // Lane transition
    if (this.laneProgress < 1) {
      this.laneProgress = Math.min(1, this.laneProgress + dt / Config.PLAYER_LANE_SWITCH_DURATION);
      const t = 1 - Math.pow(1 - this.laneProgress, 3); // ease-out cubic
      this.position.x = this.laneStartX + (this.laneTargetX - this.laneStartX) * t;
      if (this.laneProgress >= 1) this.currentLane = this.targetLane;
    }

    this.mesh.position.copyFrom(this.position);

    // Damage flash decay
    if (this.flashTimer > 0) {
      this.flashTimer -= dt;
      if (this.flashTimer <= 0) {
        this.bodyMat.emissiveColor = Color3.FromHexString(Config.COLORS.PLAYER).scale(0.2);
      }
    }

    // Fire timer
    this.fireTimer += dt;
  }

  /** Returns true if weapon is ready to fire, and resets the timer */
  public tryFire(): boolean {
    const weapon = this.getWeaponConfig();
    const interval = 1 / weapon.fireRate;
    if (this.fireTimer >= interval) {
      this.fireTimer = 0;
      return true;
    }
    return false;
  }

  public takeDamage(amount: number): void {
    this.hp = Math.max(0, this.hp - amount);
    this.flashTimer = 0.2;
    this.bodyMat.emissiveColor = new Color3(1, 0.2, 0.2);
  }

  public heal(amount: number): void {
    this.hp = Math.min(this.maxHp, this.hp + amount);
  }

  public setWeapon(type: WeaponType): void {
    this.weapon = type;
    this.fireTimer = 0;
    this.equipWeaponModel(type);
  }

  private equipWeaponModel(type: WeaponType): void {
    if (this.gunMesh) {
      this.gunMesh.dispose();
      this.gunMesh = null;
    }
    this.gunMesh = WeaponModelBuilder.create(this.scene, type);
    this.gunMesh.scaling.setAll(0.8);
    this.gunMesh.position.set(0.4, 0.8, 0.3);
    this.gunMesh.parent = this.mesh;
  }

  public getWeaponConfig(): WeaponConfig { return WEAPONS[this.weapon]; }
  public getWeaponType(): WeaponType { return this.weapon; }
  public getHP(): number { return this.hp; }
  public getMaxHP(): number { return this.maxHp; }
  public isAlive(): boolean { return this.hp > 0; }
  public getPosition(): Vector3 { return this.position.clone(); }
  public getMuzzlePosition(): Vector3 { return new Vector3(this.position.x, 1, this.position.z + 1); }
  public getCurrentLane(): Lane { return this.currentLane; }

  public reset(): void {
    this.hp = Config.INITIAL_HP;
    this.maxHp = Config.INITIAL_HP;
    this.weapon = WeaponType.PISTOL;
    this.fireTimer = 0;
    this.equipWeaponModel(WeaponType.PISTOL);
    this.currentLane = Lane.CENTER;
    this.targetLane = Lane.CENTER;
    this.laneProgress = 1;
    this.position.set(Config.LANES.CENTER, Config.PLAYER_HEIGHT, Config.PLAYER_Z_POSITION);
    this.mesh.position.copyFrom(this.position);
  }
}
