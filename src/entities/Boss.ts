import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh, TransformNode,
} from '@babylonjs/core';
import { Config, Lane } from '@/core/Config';

export class Boss {
  public active: boolean = false;
  public hp: number = 0;
  public maxHp: number = 0;
  public position: Vector3;
  public defeated: boolean = false;

  // Attack system
  private attackTimer: number = 0;
  private attackInterval: number = 2.0; // seconds between attacks
  private phase: number = 1;

  // Projectiles that boss fires at player
  public projectiles: { position: Vector3; lane: Lane; active: boolean; mesh: Mesh }[] = [];

  private mesh: TransformNode;
  private bodyMesh: Mesh;
  private mat: StandardMaterial;
  private floatTime: number = 0;
  private targetZ: number = 40; // Boss stops here

  constructor(scene: Scene) {
    this.position = new Vector3(0, 0, Config.ENEMY_SPAWN_DISTANCE);

    // Build boss mesh — large, menacing mech
    this.mesh = new TransformNode('boss', scene);

    this.mat = new StandardMaterial('bossMat', scene);
    this.mat.diffuseColor = Color3.FromHexString(Config.COLORS.BOSS);
    this.mat.emissiveColor = Color3.FromHexString(Config.COLORS.BOSS).scale(0.3);

    const darkMat = new StandardMaterial('bossDarkMat', scene);
    darkMat.diffuseColor = new Color3(0.25, 0.08, 0.08);
    darkMat.emissiveColor = new Color3(0.15, 0.02, 0.02);

    // Torso — wide, imposing
    this.bodyMesh = MeshBuilder.CreateBox('bossBody', { width: 5, height: 3.5, depth: 2.5 }, scene);
    this.bodyMesh.position.y = 2.5;
    this.bodyMesh.material = this.mat;
    this.bodyMesh.parent = this.mesh;

    // Head — angular helmet
    const head = MeshBuilder.CreateBox('bossHead', { width: 2.0, height: 1.5, depth: 1.5 }, scene);
    head.position.y = 5.0;
    head.material = darkMat;
    head.parent = this.mesh;

    // Horns — large spikes coming off the head
    for (const side of [-1, 1]) {
      const horn = MeshBuilder.CreateCylinder(`horn${side}`, { diameterTop: 0, diameterBottom: 0.6, height: 2.5, tessellation: 4 }, scene);
      horn.position.set(side * 1.2, 5.8, 0);
      horn.rotation.z = side * -0.4;
      horn.material = this.mat;
      horn.parent = this.mesh;
    }

    // Eyes — glowing, menacing
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

    // Legs — thick pillars
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

    // Chest plate / core (glowing)
    const core = MeshBuilder.CreateSphere('bossCore', { diameter: 1.2, segments: 8 }, scene);
    core.position.set(0, 2.5, -1.3);
    core.material = eyeMat; // Same glowing yellow
    core.parent = this.mesh;

    // Pre-create projectile pool (6 projectiles)
    const projMat = new StandardMaterial('projMat', scene);
    projMat.diffuseColor = new Color3(1, 0.3, 0);
    projMat.emissiveColor = new Color3(1, 0.3, 0).scale(0.8);

    for (let i = 0; i < 6; i++) {
      const projMesh = MeshBuilder.CreateSphere(`proj_${i}`, { diameter: 0.8, segments: 6 }, scene);
      projMesh.material = projMat;
      projMesh.setEnabled(false);
      projMesh.isPickable = false;
      this.projectiles.push({
        position: Vector3.Zero(),
        lane: Lane.CENTER,
        active: false,
        mesh: projMesh,
      });
    }

    this.mesh.setEnabled(false);
  }

  public activate(hp: number): void {
    this.active = true;
    this.defeated = false;
    this.hp = hp;
    this.maxHp = hp;
    this.phase = 1;
    this.attackTimer = 0;
    this.attackInterval = 2.0;
    this.position.set(0, 0, Config.ENEMY_SPAWN_DISTANCE);
    this.targetZ = 40;
    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
    for (const p of this.projectiles) {
      p.active = false;
      p.mesh.setEnabled(false);
    }
  }

  public update(dt: number): void {
    if (!this.active) return;

    // Move toward target Z
    if (this.position.z > this.targetZ) {
      this.position.z -= 8 * dt;
      if (this.position.z < this.targetZ) this.position.z = this.targetZ;
    }

    // Float/menace animation
    this.floatTime += dt;
    this.mesh.position.set(
      this.position.x + Math.sin(this.floatTime * 1.5) * 0.5,
      this.position.y + Math.sin(this.floatTime * 2) * 0.3,
      this.position.z
    );

    // Determine phase from HP
    const hpPct = this.hp / this.maxHp;
    if (hpPct < 0.33) {
      this.phase = 3;
      this.attackInterval = 0.8;
    } else if (hpPct < 0.66) {
      this.phase = 2;
      this.attackInterval = 1.3;
    }

    // Flash on damage
    // (handled by takeDamage)

    // Attack timer
    this.attackTimer += dt;
    if (this.attackTimer >= this.attackInterval && this.position.z <= this.targetZ + 1) {
      this.attack();
      this.attackTimer = 0;
    }

    // Update projectiles
    for (const p of this.projectiles) {
      if (!p.active) continue;
      p.position.z -= 25 * dt; // Fast projectiles
      p.mesh.position.copyFrom(p.position);

      // Despawn if past player
      if (p.position.z < Config.PLAYER_Z_POSITION - 5) {
        p.active = false;
        p.mesh.setEnabled(false);
      }
    }
  }

  private attack(): void {
    // Pick target lane(s) based on phase
    const targetLanes: Lane[] = [];

    if (this.phase === 1) {
      // Phase 1: single lane
      const lanes = [Lane.LEFT, Lane.CENTER, Lane.RIGHT];
      targetLanes.push(lanes[Math.floor(Math.random() * lanes.length)]);
    } else if (this.phase === 2) {
      // Phase 2: two lanes (player must find safe lane)
      const lanes = [Lane.LEFT, Lane.CENTER, Lane.RIGHT];
      const safe = Math.floor(Math.random() * lanes.length);
      targetLanes.push(...lanes.filter((_, i) => i !== safe));
    } else {
      // Phase 3: rapid single lane, randomly targeted
      const lanes = [Lane.LEFT, Lane.CENTER, Lane.RIGHT];
      targetLanes.push(lanes[Math.floor(Math.random() * lanes.length)]);
    }

    // Fire projectile for each target lane
    for (const lane of targetLanes) {
      const proj = this.projectiles.find(p => !p.active);
      if (!proj) continue;

      const laneX = lane === Lane.LEFT ? Config.LANES.LEFT
        : lane === Lane.RIGHT ? Config.LANES.RIGHT : Config.LANES.CENTER;

      proj.active = true;
      proj.lane = lane;
      proj.position.set(laneX, 1.5, this.position.z - 2);
      proj.mesh.setEnabled(true);
      proj.mesh.position.copyFrom(proj.position);
    }
  }

  /** Returns true if boss is defeated */
  public takeDamage(amount: number): boolean {
    this.hp = Math.max(0, this.hp - amount);

    // Flash white
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
    return 3.0; // Big target
  }

  /** Check if any active projectile hits the player position */
  public checkProjectileHits(playerX: number, playerZ: number, playerRadius: number): number {
    let hits = 0;
    for (const p of this.projectiles) {
      if (!p.active) continue;
      const dx = p.position.x - playerX;
      const dz = p.position.z - playerZ;
      const dist = Math.sqrt(dx * dx + dz * dz);
      if (dist < playerRadius + 0.4) {
        p.active = false;
        p.mesh.setEnabled(false);
        hits++;
      }
    }
    return hits;
  }
}
