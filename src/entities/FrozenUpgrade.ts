import { Scene, Vector3, MeshBuilder, StandardMaterial, Color3, Mesh } from '@babylonjs/core';
import { Config, WeaponType } from '@/core/Config';

export type FrozenReward = WeaponType | 'heal';

const REWARD_COLORS: Record<FrozenReward, string> = {
  [WeaponType.SMG]:     '#FCD34D',
  [WeaponType.SHOTGUN]: '#F97316',
  [WeaponType.LASER]:   '#60A5FA',
  [WeaponType.ROCKET]:  '#EF4444',
  [WeaponType.PISTOL]:  '#FBBF24',
  heal:                 '#22C55E',
};

const LANE_X: Record<number, number> = {
  [-1]: Config.LANES.LEFT,
  [0]:  Config.LANES.CENTER,
  [1]:  Config.LANES.RIGHT,
};

export class FrozenUpgrade {
  public active: boolean = false;
  public thawed: boolean = false;
  public collected: boolean = false;
  public position: Vector3;
  public lane: number = 0;
  public reward: FrozenReward = WeaponType.SMG;

  private iceHp: number = Config.FROZEN_ICE_HP;
  private maxIceHp: number = Config.FROZEN_ICE_HP;
  private iceMesh: Mesh;
  private rewardMesh: Mesh;
  private hpBarBg: Mesh;
  private hpBarFill: Mesh;
  private iceMat: StandardMaterial;
  private rewardMat: StandardMaterial;
  private hpFillMat: StandardMaterial;
  private floatTime: number = 0;

  constructor(scene: Scene) {
    this.position = Vector3.Zero();

    // Ice mesh — translucent cyan box
    this.iceMesh = MeshBuilder.CreateBox('frozenIce', { size: 1.8 }, scene);
    this.iceMat = new StandardMaterial('frozenIceMat', scene);
    this.iceMat.diffuseColor = Color3.FromHexString(Config.COLORS.FROZEN_ICE);
    this.iceMat.emissiveColor = Color3.FromHexString(Config.COLORS.FROZEN_ICE).scale(0.3);
    this.iceMat.alpha = 0.6;
    this.iceMat.backFaceCulling = false;
    this.iceMesh.material = this.iceMat;
    this.iceMesh.isPickable = false;
    this.iceMesh.setEnabled(false);

    // Reward mesh — smaller sphere inside the ice
    this.rewardMesh = MeshBuilder.CreateSphere('frozenReward', { diameter: 0.9, segments: 8 }, scene);
    this.rewardMat = new StandardMaterial('frozenRewardMat', scene);
    this.rewardMat.diffuseColor = Color3.White();
    this.rewardMat.emissiveColor = Color3.White().scale(0.5);
    this.rewardMesh.material = this.rewardMat;
    this.rewardMesh.isPickable = false;
    this.rewardMesh.setEnabled(false);

    // HP bar background
    this.hpBarBg = MeshBuilder.CreatePlane('frozenHpBg', { width: 1.8, height: 0.18 }, scene);
    const bgMat = new StandardMaterial('frozenHpBgMat', scene);
    bgMat.diffuseColor = new Color3(0.2, 0.2, 0.2);
    bgMat.emissiveColor = new Color3(0.1, 0.1, 0.1);
    bgMat.backFaceCulling = false;
    this.hpBarBg.material = bgMat;
    this.hpBarBg.billboardMode = Mesh.BILLBOARDMODE_ALL;
    this.hpBarBg.renderingGroupId = 1;
    this.hpBarBg.isPickable = false;
    this.hpBarBg.setEnabled(false);

    // HP bar fill
    this.hpBarFill = MeshBuilder.CreatePlane('frozenHpFill', { width: 1.7, height: 0.12 }, scene);
    this.hpFillMat = new StandardMaterial('frozenHpFillMat', scene);
    this.hpFillMat.diffuseColor = Color3.FromHexString(Config.COLORS.FROZEN_ICE);
    this.hpFillMat.emissiveColor = Color3.FromHexString(Config.COLORS.FROZEN_ICE).scale(0.5);
    this.hpFillMat.backFaceCulling = false;
    this.hpBarFill.material = this.hpFillMat;
    this.hpBarFill.billboardMode = Mesh.BILLBOARDMODE_ALL;
    this.hpBarFill.renderingGroupId = 1;
    this.hpBarFill.isPickable = false;
    this.hpBarFill.setEnabled(false);
  }

  public activate(reward: FrozenReward, laneEnum: number, z: number): void {
    this.active = true;
    this.thawed = false;
    this.collected = false;
    this.reward = reward;
    this.lane = laneEnum;
    this.iceHp = Config.FROZEN_ICE_HP;
    this.maxIceHp = Config.FROZEN_ICE_HP;
    this.floatTime = 0;

    const x = LANE_X[laneEnum] ?? Config.LANES.CENTER;
    this.position.set(x, 1.0, z);

    // Apply reward color
    const colorHex = REWARD_COLORS[reward] ?? '#FFFFFF';
    const rewardColor = Color3.FromHexString(colorHex);
    this.rewardMat.diffuseColor = rewardColor;
    this.rewardMat.emissiveColor = rewardColor.scale(0.5);

    // Reset ice opacity
    this.iceMat.alpha = 0.6;

    this.iceMesh.position.copyFrom(this.position);
    this.rewardMesh.position.copyFrom(this.position);

    this.iceMesh.setEnabled(true);
    this.rewardMesh.setEnabled(false);
    this.hpBarBg.setEnabled(true);
    this.hpBarFill.setEnabled(true);
    this.hpBarFill.scaling.x = 1;
  }

  public deactivate(): void {
    this.active = false;
    this.iceMesh.setEnabled(false);
    this.rewardMesh.setEnabled(false);
    this.hpBarBg.setEnabled(false);
    this.hpBarFill.setEnabled(false);
  }

  public update(dt: number): void {
    if (!this.active) return;

    // Move toward player
    this.position.z -= Config.FROZEN_SPEED * dt;

    // Float/bob animation (only when thawed)
    if (this.thawed) {
      this.floatTime += dt * 2.5;
      this.position.y = 1.0 + Math.sin(this.floatTime) * 0.3;
    }

    if (this.thawed) {
      // Show only reward mesh, bobbing
      this.rewardMesh.position.copyFrom(this.position);
      this.iceMesh.setEnabled(false);
      this.hpBarBg.setEnabled(false);
      this.hpBarFill.setEnabled(false);
    } else {
      // Show ice mesh with HP bar
      this.iceMesh.position.copyFrom(this.position);
      this.rewardMesh.position.copyFrom(this.position);

      const barY = this.position.y + 1.4;
      this.hpBarBg.position.set(this.position.x, barY, this.position.z);
      this.hpBarFill.position.set(this.position.x, barY, this.position.z);
    }

    // Despawn if past player
    if (this.position.z < -15) {
      this.deactivate();
    }
  }

  public takeDamage(amount: number): boolean {
    if (this.thawed) return false;

    this.iceHp = Math.max(0, this.iceHp - amount);

    const hpRatio = this.iceHp / this.maxIceHp;
    this.hpBarFill.scaling.x = hpRatio;

    // Ice becomes more transparent as HP decreases (reward more visible)
    this.iceMat.alpha = 0.15 + hpRatio * 0.45;

    if (this.iceHp <= 0) {
      this.thawed = true;
      this.iceMesh.setEnabled(false);
      this.rewardMesh.setEnabled(true);
      return true;
    }

    return false;
  }

  public getCollisionInfo(): { x: number; z: number; radius: number; active: boolean } {
    return {
      x: this.position.x,
      z: this.position.z,
      radius: 1.2,
      active: this.active && !this.thawed,
    };
  }
}
