import { Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh } from '@babylonjs/core';
import { Config } from '@/core/Config';

export class Bullet {
  public active: boolean = false;
  public position: Vector3;
  public damage: number = 1;
  public penetration: number = 1;  // How many enemies it can pass through
  public splashRadius: number = 0; // 0 = no splash, >0 = damages nearby enemies

  private mesh: Mesh;
  private velocity: Vector3 = Vector3.Zero();
  private distanceTraveled: number = 0;
  private maxRange: number = Config.BULLET_DESPAWN_Z; // Default: full range
  private startZ: number = 0;

  constructor(scene: Scene) {
    this.position = Vector3.Zero();

    this.mesh = MeshBuilder.CreateBox('bullet', { width: 0.12, height: 0.12, depth: 0.4 }, scene);
    const mat = new StandardMaterial('bulletMat', scene);
    mat.diffuseColor = Color3.FromHexString(Config.COLORS.BULLET);
    mat.emissiveColor = Color3.FromHexString(Config.COLORS.BULLET).scale(0.8);
    mat.freeze();
    this.mesh.material = mat;
    this.mesh.isPickable = false;
    this.mesh.setEnabled(false);
  }

  public activate(
    pos: Vector3,
    damage: number,
    spreadX: number = 0,
    maxRange: number = Config.BULLET_DESPAWN_Z,
    penetration: number = 1,
    splashRadius: number = 0
  ): void {
    this.active = true;
    this.position.copyFrom(pos);
    this.damage = damage;
    this.penetration = penetration;
    this.splashRadius = splashRadius;
    this.maxRange = maxRange;
    this.startZ = pos.z;
    this.distanceTraveled = 0;
    this.velocity.set(spreadX * 8, 0, Config.BULLET_SPEED);
    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);
  }

  /** Called when bullet hits something. Returns true if bullet should deactivate. */
  public onHit(): boolean {
    this.penetration--;
    return this.penetration <= 0;
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

    this.position.addInPlace(this.velocity.scale(dt));
    this.mesh.position.copyFrom(this.position);

    this.distanceTraveled = this.position.z - this.startZ;

    // Deactivate if past max range or off screen
    if (this.distanceTraveled > this.maxRange || this.position.z > Config.BULLET_DESPAWN_Z) {
      this.deactivate();
    }
  }
}
