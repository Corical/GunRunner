import { Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh } from '@babylonjs/core';
import { Config } from '@/core/Config';

export class Bullet {
  public active: boolean = false;
  public position: Vector3;
  public damage: number = 1;

  private mesh: Mesh;
  private velocity: Vector3 = Vector3.Zero();

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

  public activate(pos: Vector3, damage: number, spreadX: number = 0): void {
    this.active = true;
    this.position.copyFrom(pos);
    this.damage = damage;
    this.velocity.set(spreadX * 8, 0, Config.BULLET_SPEED);
    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

    this.position.addInPlace(this.velocity.scale(dt));
    this.mesh.position.copyFrom(this.position);

    if (this.position.z > Config.BULLET_DESPAWN_Z) {
      this.deactivate();
    }
  }
}
