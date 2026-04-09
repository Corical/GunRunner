import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh, TransformNode,
} from '@babylonjs/core';
import { Config } from '@/core/Config';

export class Boss {
  public active: boolean = false;
  public hp: number = 0;
  public maxHp: number = 0;
  public position: Vector3;
  public defeated: boolean = false;

  private mesh: TransformNode;
  private bodyMesh: Mesh;
  private mat: StandardMaterial;
  private floatTime: number = 0;
  private speed: number = 5; // Slow march toward player

  constructor(scene: Scene) {
    this.position = new Vector3(0, 0, Config.ENEMY_SPAWN_DISTANCE);

    this.mesh = new TransformNode('boss', scene);

    this.mat = new StandardMaterial('bossMat', scene);
    this.mat.diffuseColor = Color3.FromHexString(Config.COLORS.BOSS);
    this.mat.emissiveColor = Color3.FromHexString(Config.COLORS.BOSS).scale(0.3);

    const darkMat = new StandardMaterial('bossDarkMat', scene);
    darkMat.diffuseColor = new Color3(0.25, 0.08, 0.08);
    darkMat.emissiveColor = new Color3(0.15, 0.02, 0.02);

    // Torso
    this.bodyMesh = MeshBuilder.CreateBox('bossBody', { width: 5, height: 3.5, depth: 2.5 }, scene);
    this.bodyMesh.position.y = 2.5;
    this.bodyMesh.material = this.mat;
    this.bodyMesh.parent = this.mesh;

    // Head
    const head = MeshBuilder.CreateBox('bossHead', { width: 2.0, height: 1.5, depth: 1.5 }, scene);
    head.position.y = 5.0;
    head.material = darkMat;
    head.parent = this.mesh;

    // Horns
    for (const side of [-1, 1]) {
      const horn = MeshBuilder.CreateCylinder(`horn${side}`, { diameterTop: 0, diameterBottom: 0.6, height: 2.5, tessellation: 4 }, scene);
      horn.position.set(side * 1.2, 5.8, 0);
      horn.rotation.z = side * -0.4;
      horn.material = this.mat;
      horn.parent = this.mesh;
    }

    // Eyes
    const eyeMat = new StandardMaterial('eyeMat', scene);
    eyeMat.diffuseColor = new Color3(1, 0.8, 0);
    eyeMat.emissiveColor = new Color3(1, 0.9, 0.2);

    for (const side of [-1, 1]) {
      const eye = MeshBuilder.CreateSphere(`eye${side}`, { diameter: 0.5, segments: 6 }, scene);
      eye.position.set(side * 0.55, 5.2, -0.8);
      eye.material = eyeMat;
      eye.parent = this.mesh;
    }

    // Shoulder cannons
    for (const side of [-1, 1]) {
      const shoulder = MeshBuilder.CreateBox(`shoulder${side}`, { width: 1.5, height: 1.0, depth: 1.5 }, scene);
      shoulder.position.set(side * 3.2, 3.5, 0);
      shoulder.material = this.mat;
      shoulder.parent = this.mesh;

      const cannon = MeshBuilder.CreateCylinder(`cannon${side}`, { diameter: 0.6, height: 2, tessellation: 6 }, scene);
      cannon.rotation.x = Math.PI / 2;
      cannon.position.set(side * 3.2, 3.8, -1.5);
      cannon.material = darkMat;
      cannon.parent = this.mesh;
    }

    // Legs
    for (const side of [-1, 1]) {
      const leg = MeshBuilder.CreateBox(`leg${side}`, { width: 1.2, height: 2.5, depth: 1.2 }, scene);
      leg.position.set(side * 1.5, -0.5, 0);
      leg.material = darkMat;
      leg.parent = this.mesh;

      const foot = MeshBuilder.CreateBox(`foot${side}`, { width: 1.5, height: 0.4, depth: 1.8 }, scene);
      foot.position.set(side * 1.5, -1.7, 0.2);
      foot.material = this.mat;
      foot.parent = this.mesh;
    }

    // Glowing core
    const core = MeshBuilder.CreateSphere('bossCore', { diameter: 1.2, segments: 8 }, scene);
    core.position.set(0, 2.5, -1.3);
    core.material = eyeMat;
    core.parent = this.mesh;

    this.mesh.setEnabled(false);
  }

  public activate(hp: number): void {
    this.active = true;
    this.defeated = false;
    this.hp = hp;
    this.maxHp = hp;
    this.speed = 5;
    this.position.set(0, 0, Config.ENEMY_SPAWN_DISTANCE);
    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

    // Keep marching toward player — never stops
    this.position.z -= this.speed * dt;

    // Speed up as HP drops — more urgent
    const hpPct = this.hp / this.maxHp;
    this.speed = 5 + (1 - hpPct) * 4; // 5 at full HP, 9 at near-death

    // Menacing sway
    this.floatTime += dt;
    this.mesh.position.set(
      this.position.x + Math.sin(this.floatTime * 1.5) * 0.5,
      this.position.y + Math.sin(this.floatTime * 2) * 0.3,
      this.position.z
    );
  }

  /** Check if boss has reached the player — deals heavy damage */
  public checkPlayerContact(playerX: number, playerZ: number, playerRadius: number): boolean {
    if (!this.active) return false;
    const dx = Math.abs(this.position.x - playerX);
    const dz = this.position.z - playerZ;
    // Boss is wide (fills road), only check Z proximity
    if (dz < playerRadius + this.getCollisionRadius() && dx < 4) {
      return true;
    }
    return false;
  }

  /** Returns true if boss is defeated */
  public takeDamage(amount: number): boolean {
    this.hp = Math.max(0, this.hp - amount);

    this.mat.emissiveColor = new Color3(1, 1, 1);
    setTimeout(() => {
      if (this.active) {
        this.mat.emissiveColor = Color3.FromHexString(Config.COLORS.BOSS).scale(0.3);
      }
    }, 80);

    if (this.hp <= 0) {
      this.defeated = true;
      this.deactivate();
      return true;
    }
    return false;
  }

  public getCollisionRadius(): number {
    return 3.0;
  }
}
