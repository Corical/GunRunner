import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh,
} from '@babylonjs/core';
import { Config, EnemyType, ENEMIES, EnemyConfig } from '@/core/Config';

export class Enemy {
  public active: boolean = false;
  public position: Vector3;
  public targetX: number = 0;  // For flankers — smooth lateral movement target
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

  // Cache meshes by type to avoid create/dispose every activation
  private cachedType: EnemyType | null = null;

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

  public activate(type: EnemyType, xPos: number, z: number): void {
    this.active = true;
    this.type = type;
    this.config = ENEMIES[type];
    this.hp = this.config.hp;
    this.maxHp = this.config.hp;
    this.targetX = xPos;
    this.position.set(xPos, this.config.size * 0.5, z);

    // Update material color
    const color = Color3.FromHexString(this.config.color);
    this.mat.diffuseColor = color;
    this.mat.emissiveColor = color.scale(0.3);

    // Only rebuild mesh if type changed — reuse cached mesh otherwise
    if (this.cachedType !== type) {
      this.buildMesh();
      this.cachedType = type;
    }

    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);

    if (this.maxHp > 1) this.createHPBar();

    this.laneSwitchTimer = 2 + Math.random() * 3;
  }

  private buildMesh(): void {
    // Dispose old mesh
    this.mesh.dispose();
    if (this.shieldMesh) { this.shieldMesh.dispose(); this.shieldMesh = null; }

    try {
      switch (this.type) {
        case EnemyType.BASIC: this.buildBasic(); break;
        case EnemyType.ARMORED: this.buildArmored(); break;
        case EnemyType.FAST: this.buildFast(); break;
        case EnemyType.SHIELDED: this.buildShielded(); break;
        case EnemyType.HEALER: this.buildHealer(); break;
        case EnemyType.SPLITTER: this.buildSplitter(); break;
        case EnemyType.BOMBER: this.buildBomber(); break;
        default:
          console.warn('Unknown enemy type:', this.type);
          this.mesh = MeshBuilder.CreateBox('fallback', { size: 1 }, this.scene);
      }
    } catch (e) {
      console.error(`Failed to build enemy mesh for type ${this.type}:`, e);
      this.mesh = MeshBuilder.CreateBox('fallback', { size: 1 }, this.scene);
    }

    this.mesh.material = this.mat;
    this.mesh.isPickable = false;
  }

  private mergeParts(parts: Mesh[], name: string): void {
    // MergeMeshes with disposeSource=false so we can fallback if merge fails
    const merged = Mesh.MergeMeshes(parts, false, false);
    if (merged) {
      // Dispose originals manually after successful merge
      parts.forEach(p => p.dispose());
      merged.name = name;
      this.mesh = merged;
    } else {
      // Merge failed — use first part, dispose the rest
      this.mesh = parts[0];
      for (let i = 1; i < parts.length; i++) parts[i].dispose();
      this.mesh.name = name;
    }
  }

  private buildBasic(): void {
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

    this.mergeParts([body, head, arms, lLeg, rLeg], 'enemy_basic');
  }

  private buildArmored(): void {
    const body = MeshBuilder.CreateBox('eb', { width: 1.4, height: 1.5, depth: 0.9 }, this.scene);
    body.position.y = 0.75; body.material = this.mat;

    const lShoulder = MeshBuilder.CreateBox('els', { width: 0.5, height: 0.3, depth: 0.5 }, this.scene);
    lShoulder.position.set(-0.85, 1.3, 0); lShoulder.material = this.mat;

    const rShoulder = MeshBuilder.CreateBox('ers', { width: 0.5, height: 0.3, depth: 0.5 }, this.scene);
    rShoulder.position.set(0.85, 1.3, 0); rShoulder.material = this.mat;

    const head = MeshBuilder.CreateSphere('eh', { diameter: 0.45, segments: 6 }, this.scene);
    head.position.y = 1.75; head.material = this.mat;

    const plate = MeshBuilder.CreateBox('ep', { width: 1.0, height: 0.6, depth: 0.15 }, this.scene);
    plate.position.set(0, 0.9, -0.45); plate.material = this.mat;

    this.mergeParts([body, lShoulder, rShoulder, head, plate], 'enemy_armored');
  }

  private buildFast(): void {
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

    this.mergeParts([cone, lFin, rFin, tail], 'enemy_fast');
  }

  private buildShielded(): void {
    // Distinct body — darker grey, stocky, holding the shield
    const body = MeshBuilder.CreateCylinder('eb', { diameter: 0.8, height: 1.2, tessellation: 6 }, this.scene);
    body.position.y = 0.6; body.material = this.mat;

    const head = MeshBuilder.CreateSphere('eh', { diameter: 0.45, segments: 6 }, this.scene);
    head.position.y = 1.4; head.material = this.mat;

    // Shield arm — box sticking forward
    const arm = MeshBuilder.CreateBox('ea', { width: 0.15, height: 0.15, depth: 0.5 }, this.scene);
    arm.position.set(-0.3, 0.7, -0.35); arm.material = this.mat;

    this.mergeParts([body, head, arm], 'enemy_shielded');

    // Shield — thin curved disc in front, NOT covering the body from above
    this.shieldMesh = MeshBuilder.CreateDisc('eshield', { radius: 0.8, tessellation: 12 }, this.scene);
    this.shieldMesh.rotation.y = Math.PI; // Face toward player
    this.shieldMesh.position.set(-0.15, 0.7, -0.8);
    const shieldMat = new StandardMaterial('shieldMat', this.scene);
    shieldMat.diffuseColor = Color3.FromHexString('#67E8F9');
    shieldMat.emissiveColor = Color3.FromHexString('#67E8F9').scale(0.6);
    shieldMat.alpha = 0.4;
    shieldMat.backFaceCulling = false;
    this.shieldMesh.material = shieldMat;
    this.shieldMesh.isPickable = false;
    this.shieldMesh.parent = this.mesh;
  }

  private buildHealer(): void {
    // Green medic — cross on top, rounded body
    const body = MeshBuilder.CreateSphere('eb', { diameter: 0.9, segments: 8 }, this.scene);
    body.position.y = 0.5; body.material = this.mat;

    // Cross on top
    const crossH = MeshBuilder.CreateBox('ech', { width: 0.7, height: 0.15, depth: 0.15 }, this.scene);
    crossH.position.y = 1.2; crossH.material = this.mat;

    const crossV = MeshBuilder.CreateBox('ecv', { width: 0.15, height: 0.7, depth: 0.15 }, this.scene);
    crossV.position.y = 1.2; crossV.material = this.mat;

    // Aura ring
    const ring = MeshBuilder.CreateTorus('ering', { diameter: 1.2, thickness: 0.08, tessellation: 12 }, this.scene);
    ring.position.y = 0.5; ring.material = this.mat;

    this.mergeParts([body, crossH, crossV, ring], 'enemy_healer');
  }

  private buildSplitter(): void {
    // Pink blob that splits — sphere body with smaller spheres budding off
    const core = MeshBuilder.CreateSphere('ec', { diameter: 1.0, segments: 8 }, this.scene);
    core.position.y = 0.5; core.material = this.mat;

    const bud1 = MeshBuilder.CreateSphere('eb1', { diameter: 0.5, segments: 6 }, this.scene);
    bud1.position.set(0.5, 0.7, 0); bud1.material = this.mat;

    const bud2 = MeshBuilder.CreateSphere('eb2', { diameter: 0.5, segments: 6 }, this.scene);
    bud2.position.set(-0.4, 0.3, 0.3); bud2.material = this.mat;

    const bud3 = MeshBuilder.CreateSphere('eb3', { diameter: 0.4, segments: 6 }, this.scene);
    bud3.position.set(0.1, 0.9, -0.3); bud3.material = this.mat;

    this.mergeParts([core, bud1, bud2, bud3], 'enemy_splitter');
  }

  private buildBomber(): void {
    // Brown bomb with fuse — round body, fuse sticking up
    const body = MeshBuilder.CreateSphere('eb', { diameter: 0.9, segments: 8 }, this.scene);
    body.position.y = 0.45; body.material = this.mat;

    // Fuse
    const fuse = MeshBuilder.CreateCylinder('ef', { diameter: 0.08, height: 0.5, tessellation: 4 }, this.scene);
    fuse.position.set(0, 1.1, 0); fuse.rotation.z = 0.3; fuse.material = this.mat;

    // Spark at tip (small bright sphere)
    const spark = MeshBuilder.CreateSphere('es', { diameter: 0.18, segments: 4 }, this.scene);
    spark.position.set(0.08, 1.35, 0); spark.material = this.mat;

    // Wings (bomber swoops in)
    const lWing = MeshBuilder.CreateBox('elw', { width: 0.5, height: 0.05, depth: 0.3 }, this.scene);
    lWing.position.set(-0.5, 0.5, 0); lWing.rotation.z = -0.3; lWing.material = this.mat;

    const rWing = MeshBuilder.CreateBox('erw', { width: 0.5, height: 0.05, depth: 0.3 }, this.scene);
    rWing.position.set(0.5, 0.5, 0); rWing.rotation.z = 0.3; rWing.material = this.mat;

    this.mergeParts([body, fuse, spark, lWing, rWing], 'enemy_bomber');
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

    // Flankers weave laterally toward a random target X
    if (this.config.switchesLanes) {
      this.laneSwitchTimer -= dt;
      if (this.laneSwitchTimer <= 0) {
        this.laneSwitchTimer = 1.5 + Math.random() * 2;
        const roadHalf = Config.ROAD_WIDTH / 2 - 1;
        this.targetX = (Math.random() - 0.5) * 2 * roadHalf;
      }
      // Smooth movement toward target X
      const dx = this.targetX - this.position.x;
      if (Math.abs(dx) > 0.1) {
        this.position.x += Math.sign(dx) * Math.min(Math.abs(dx), 8 * dt);
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
