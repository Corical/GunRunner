import {
  Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh, TransformNode,
} from '@babylonjs/core';
import { TowerType, TOWERS, TowerConfig } from '@/core/Config';
import { Enemy } from './Enemy';

const TOWER_Z = 50; // Deploy halfway down the road

export class Tower {
  public active: boolean = false;
  public type: TowerType = TowerType.FREEZE;
  public config!: TowerConfig;
  public position: Vector3;
  public timeLeft: number = 0;

  private mesh: TransformNode;
  private baseMesh: Mesh;
  private topMesh: Mesh;
  private rangeMesh: Mesh;
  private mat: StandardMaterial;
  private rangeMat: StandardMaterial;
  private scene: Scene;
  private rotTime: number = 0;

  constructor(scene: Scene) {
    this.scene = scene;
    this.position = new Vector3(0, 0, TOWER_Z);

    this.mesh = new TransformNode('tower', this.scene);

    this.mat = new StandardMaterial('towerMat', this.scene);
    this.mat.diffuseColor = Color3.White();
    this.mat.emissiveColor = Color3.White().scale(0.3);

    // Base — cylinder pedestal
    this.baseMesh = MeshBuilder.CreateCylinder('tBase', { diameter: 1.0, height: 0.6, tessellation: 8 }, this.scene);
    this.baseMesh.position.y = 0.3;
    this.baseMesh.material = this.mat;
    this.baseMesh.parent = this.mesh;

    // Top — changes per type, start with a sphere placeholder
    this.topMesh = MeshBuilder.CreateSphere('tTop', { diameter: 0.8, segments: 6 }, this.scene);
    this.topMesh.position.y = 1.0;
    this.topMesh.material = this.mat;
    this.topMesh.parent = this.mesh;

    // Range indicator — flat transparent disc
    this.rangeMat = new StandardMaterial('tRangeMat', this.scene);
    this.rangeMat.diffuseColor = Color3.White();
    this.rangeMat.emissiveColor = Color3.White().scale(0.2);
    this.rangeMat.alpha = 0.1;
    this.rangeMat.backFaceCulling = false;

    this.rangeMesh = MeshBuilder.CreateDisc('tRange', { radius: 1, tessellation: 24 }, this.scene);
    this.rangeMesh.rotation.x = Math.PI / 2;
    this.rangeMesh.position.y = 0.05;
    this.rangeMesh.material = this.rangeMat;
    this.rangeMesh.parent = this.mesh;

    this.mesh.setEnabled(false);
  }

  public activate(type: TowerType, xPos: number): void {
    this.active = true;
    this.type = type;
    this.config = TOWERS[type];
    this.timeLeft = this.config.duration;
    this.position.set(xPos, 0, TOWER_Z);
    this.rotTime = 0;

    // Color
    const color = Color3.FromHexString(this.config.color);
    this.mat.diffuseColor = color;
    this.mat.emissiveColor = color.scale(0.4);
    this.rangeMat.diffuseColor = color;
    this.rangeMat.emissiveColor = color.scale(0.2);

    // Scale range indicator to match radius
    const rangeScale = this.config.radius;
    this.rangeMesh.scaling.set(rangeScale, rangeScale, rangeScale);

    // Rebuild top based on type
    this.topMesh.dispose();
    switch (type) {
      case TowerType.FREEZE:
        // Ice crystal — diamond shape
        this.topMesh = MeshBuilder.CreatePolyhedron('tTop', { type: 1, size: 0.4 }, this.scene);
        break;
      case TowerType.FIRE:
        // Flame — upward cone
        this.topMesh = MeshBuilder.CreateCylinder('tTop', { diameterTop: 0, diameterBottom: 0.7, height: 1.0, tessellation: 6 }, this.scene);
        break;
      case TowerType.POISON:
        // Poison — skull-like sphere with horns
        this.topMesh = MeshBuilder.CreateSphere('tTop', { diameter: 0.7, segments: 6 }, this.scene);
        break;
    }
    this.topMesh.position.y = 1.0;
    this.topMesh.material = this.mat;
    this.topMesh.parent = this.mesh;

    this.mesh.setEnabled(true);
    this.mesh.position.copyFrom(this.position);
  }

  public deactivate(): void {
    this.active = false;
    this.mesh.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

    this.timeLeft -= dt;
    if (this.timeLeft <= 0) {
      this.deactivate();
      return;
    }

    // Spin the top
    this.rotTime += dt;
    this.topMesh.rotation.y = this.rotTime * 2;

    // Pulse range indicator
    const pulse = 0.08 + Math.sin(this.rotTime * 3) * 0.04;
    this.rangeMat.alpha = pulse;

    // Fade out in last 3 seconds
    if (this.timeLeft < 3) {
      const fade = this.timeLeft / 3;
      this.mat.alpha = fade;
    } else {
      this.mat.alpha = 1;
    }
  }

  /** Apply tower effects to all enemies in range */
  public applyEffects(enemies: Enemy[]): void {
    if (!this.active) return;

    for (const enemy of enemies) {
      if (!enemy.active) continue;

      const dx = enemy.position.x - this.position.x;
      const dz = enemy.position.z - this.position.z;
      const dist = Math.sqrt(dx * dx + dz * dz);

      if (dist < this.config.radius) {
        // Freeze: slow enemies
        if (this.config.slowMultiplier < 1.0) {
          enemy.applySlow(this.config.slowMultiplier);
        }
        // Fire: burn enemies
        if (this.config.damagePerSec > 0) {
          enemy.applyBurn(true);
        }
        // Poison: apply lingering poison
        if (this.config.poisonDuration > 0) {
          enemy.applyPoison(this.config.poisonDuration);
        }
      }
    }
  }
}
