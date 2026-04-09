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

  private mesh!: Mesh;
  private shieldMesh: Mesh | null = null;
  private hpBarBg: Mesh | null = null;
  private hpBarFill: Mesh | null = null;
  private scene: Scene;
  private mat: StandardMaterial;
  private flashTimer: number = 0;
  private laneSwitchTimer: number = 0;

  constructor(scene: Scene) {
    this.scene = scene;
    this.position = Vector3.Zero();

    this.mat = new StandardMaterial('enemyMat', scene);
    this.mat.diffuseColor = Color3.Red();
    this.mat.emissiveColor = Color3.Red().scale(0.3);

    // Placeholder — gets rebuilt on activate
    this.mesh = MeshBuilder.CreateBox('enemy', { size: 0.5 }, scene);
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

    // Update material color
    const color = Color3.FromHexString(this.config.color);
    this.mat.diffuseColor = color;
    this.mat.emissiveColor = color.scale(0.3);

    // Rebuild mesh for this enemy type
    this.buildMesh();

    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);

    if (this.maxHp > 1) this.createHPBar();

    this.laneSwitchTimer = 2 + Math.random() * 3;
  }

  private buildMesh(): void {
    // Dispose old mesh
    this.mesh.dispose();
    if (this.shieldMesh) { this.shieldMesh.dispose(); this.shieldMesh = null; }

    switch (this.type) {
      case EnemyType.BASIC: this.buildBasic(); break;
      case EnemyType.ARMORED: this.buildArmored(); break;
      case EnemyType.FAST: this.buildFast(); break;
      case EnemyType.SHIELDED: this.buildShielded(); break;
    }

    this.mesh.material = this.mat;
    this.mesh.isPickable = false;
  }

  private buildBasic(): void {
    // Humanoid — body + head + arms. Scale ~1.2 so it's clearly visible
    const body = MeshBuilder.CreateCylinder('eb', { diameter: 0.7, height: 1.0, tessellation: 6 }, this.scene);
    body.position.y = 0.5; body.material = this.mat;

    const head = MeshBuilder.CreateSphere('eh', { diameter: 0.5, segments: 6 }, this.scene);
    head.position.y = 1.3; head.material = this.mat;

    const arms = MeshBuilder.CreateBox('ea', { width: 1.1, height: 0.15, depth: 0.15 }, this.scene);
    arms.position.y = 0.7; arms.material = this.mat;

    const lLeg = MeshBuilder.CreateCylinder('ell', { diameter: 0.2, height: 0.5, tessellation: 4 }, this.scene);
    lLeg.position.set(-0.2, -0.2, 0); lLeg.material = this.mat;

    const rLeg = MeshBuilder.CreateCylinder('erl', { diameter: 0.2, height: 0.5, tessellation: 4 }, this.scene);
    rLeg.position.set(0.2, -0.2, 0); rLeg.material = this.mat;

    this.mesh = Mesh.MergeMeshes([body, head, arms, lLeg, rLeg], true, false) || body;
    this.mesh.name = 'enemy_basic';
  }

  private buildArmored(): void {
    // Chunky wide tank — much bigger than basic
    const body = MeshBuilder.CreateBox('eb', { width: 1.4, height: 1.5, depth: 0.9 }, this.scene);
    body.position.y = 0.75; body.material = this.mat;

    const lShoulder = MeshBuilder.CreateBox('els', { width: 0.5, height: 0.3, depth: 0.5 }, this.scene);
    lShoulder.position.set(-0.85, 1.3, 0); lShoulder.material = this.mat;

    const rShoulder = MeshBuilder.CreateBox('ers', { width: 0.5, height: 0.3, depth: 0.5 }, this.scene);
    rShoulder.position.set(0.85, 1.3, 0); rShoulder.material = this.mat;

    const head = MeshBuilder.CreateSphere('eh', { diameter: 0.45, segments: 6 }, this.scene);
    head.position.y = 1.75; head.material = this.mat;

    // Chest plate
    const plate = MeshBuilder.CreateBox('ep', { width: 1.0, height: 0.6, depth: 0.15 }, this.scene);
    plate.position.set(0, 0.9, -0.45); plate.material = this.mat;

    this.mesh = Mesh.MergeMeshes([body, lShoulder, rShoulder, head, plate], true, false) || body;
    this.mesh.name = 'enemy_armored';
  }

  private buildFast(): void {
    // Sleek pointed cone + swept fins — clearly aerodynamic
    const cone = MeshBuilder.CreateCylinder('ec', {
      diameterTop: 0, diameterBottom: 0.7, height: 1.4, tessellation: 6,
    }, this.scene);
    cone.rotation.x = -Math.PI / 2;
    cone.position.y = 0.4; cone.material = this.mat;

    const lFin = MeshBuilder.CreateBox('elf', { width: 0.06, height: 0.5, depth: 0.5 }, this.scene);
    lFin.position.set(-0.35, 0.4, 0.3); lFin.rotation.z = -0.4; lFin.material = this.mat;

    const rFin = MeshBuilder.CreateBox('erf', { width: 0.06, height: 0.5, depth: 0.5 }, this.scene);
    rFin.position.set(0.35, 0.4, 0.3); rFin.rotation.z = 0.4; rFin.material = this.mat;

    const tail = MeshBuilder.CreateBox('et', { width: 0.06, height: 0.6, depth: 0.3 }, this.scene);
    tail.position.set(0, 0.6, 0.4); tail.material = this.mat;

    this.mesh = Mesh.MergeMeshes([cone, lFin, rFin, tail], true, false) || cone;
    this.mesh.name = 'enemy_fast';
  }

  private buildShielded(): void {
    // Body with visible translucent shield wall in front
    const body = MeshBuilder.CreateCylinder('eb', { diameter: 0.7, height: 1.0, tessellation: 6 }, this.scene);
    body.position.y = 0.5; body.material = this.mat;

    const head = MeshBuilder.CreateSphere('eh', { diameter: 0.4, segments: 6 }, this.scene);
    head.position.y = 1.2; head.material = this.mat;

    this.mesh = Mesh.MergeMeshes([body, head], true, false) || body;
    this.mesh.name = 'enemy_shielded';

    // Large translucent cyan shield in front — separate mesh for transparency
    this.shieldMesh = MeshBuilder.CreateBox('eshield', { width: 1.3, height: 1.3, depth: 0.12 }, this.scene);
    this.shieldMesh.position.z = -0.7;
    this.shieldMesh.position.y = 0.6;
    const shieldMat = new StandardMaterial('shieldMat', this.scene);
    shieldMat.diffuseColor = Color3.FromHexString('#67E8F9');
    shieldMat.emissiveColor = Color3.FromHexString('#67E8F9').scale(0.5);
    shieldMat.alpha = 0.5;
    shieldMat.backFaceCulling = false;
    this.shieldMesh.material = shieldMat;
    this.shieldMesh.isPickable = false;
    this.shieldMesh.parent = this.mesh;
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
    if (this.shieldMesh) this.shieldMesh.setEnabled(false);
    if (this.hpBarBg) this.hpBarBg.setEnabled(false);
    if (this.hpBarFill) this.hpBarFill.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

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
        this.position.x = this.lane === Lane.LEFT ? Config.LANES.LEFT
          : this.lane === Lane.RIGHT ? Config.LANES.RIGHT : Config.LANES.CENTER;
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

    // HP bar follow
    if (this.hpBarBg && this.hpBarFill) {
      this.hpBarBg.position.set(this.position.x, this.config.size + 0.5, this.position.z);
      this.hpBarFill.position.set(this.position.x, this.config.size + 0.5, this.position.z);
      this.hpBarFill.scaling.x = Math.max(0, this.hp / this.maxHp);
    }

    if (this.position.z < Config.ENEMY_DESPAWN_Z) this.deactivate();
  }

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
    return this.config ? this.config.size * 0.6 : 0.5;
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
