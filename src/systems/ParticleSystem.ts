import * as BABYLON from '@babylonjs/core';

/**
 * Manages all particle effects for GunRunner.
 * Effects auto-dispose after their animation completes.
 */
const MAX_ACTIVE_SYSTEMS = 15; // Prevent GPU overload from grenade spam

export class ParticleSystem {
  private scene: BABYLON.Scene;
  private activeSystems: BABYLON.ParticleSystem[] = [];

  constructor(scene: BABYLON.Scene) {
    this.scene = scene;
  }

  /** Check if we can spawn more particles — skip if at capacity */
  private canSpawn(): boolean {
    return this.activeSystems.length < MAX_ACTIVE_SYSTEMS;
  }

  /**
   * Muzzle flash — small yellow burst, very short lived (≈50 ms).
   */
  public createMuzzleFlash(position: BABYLON.Vector3): void {
    this.createBurst('muzzleFlash', position, 8, {
      minSize: 0.1,
      maxSize: 0.3,
      minLife: 0.05,
      maxLife: 0.12,
      color1: new BABYLON.Color4(1, 1, 0, 1),
      color2: new BABYLON.Color4(1, 0.6, 0, 0.8),
      colorDead: new BABYLON.Color4(1, 0.2, 0, 0),
      minPower: 4,
      maxPower: 8,
      gravity: BABYLON.Vector3.Zero(),
      stopAfterMs: 30,
      disposeAfterMs: 150,
      emitterRadius: 0.3,
    });
    // tracked in createBurst
  }

  /**
   * Enemy hit sparks — small red spark burst.
   */
  public createEnemyHitEffect(position: BABYLON.Vector3): void {
    this.createBurst('enemyHit', position, 8, {
      minSize: 0.15,
      maxSize: 0.4,
      minLife: 0.1,
      maxLife: 0.3,
      color1: new BABYLON.Color4(1, 0.1, 0.1, 1),
      color2: new BABYLON.Color4(1, 0.4, 0, 0.8),
      colorDead: new BABYLON.Color4(0.4, 0, 0, 0),
      minPower: 3,
      maxPower: 7,
      gravity: new BABYLON.Vector3(0, -8, 0),
      stopAfterMs: 40,
      disposeAfterMs: 400,
      emitterRadius: 0.5,
    });
    // tracked in createBurst
  }

  /**
   * Enemy death burst — larger explosion matching enemy color.
   */
  public createEnemyDeathEffect(position: BABYLON.Vector3, color: BABYLON.Color3): void {
    this.createBurst('enemyDeath', position, 25, {
      minSize: 0.2,
      maxSize: 0.7,
      minLife: 0.3,
      maxLife: 0.7,
      color1: new BABYLON.Color4(color.r, color.g, color.b, 1),
      color2: new BABYLON.Color4(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.7),
      colorDead: new BABYLON.Color4(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0),
      minPower: 5,
      maxPower: 12,
      gravity: new BABYLON.Vector3(0, -10, 0),
      stopAfterMs: 60,
      disposeAfterMs: 800,
      emitterRadius: 1.0,
    });
    // tracked in createBurst
  }

  /**
   * Ice crack — sharp cyan shards.
   */
  public createIceCrackEffect(position: BABYLON.Vector3): void {
    this.createBurst('iceCrack', position, 25, {
      minSize: 0.1,
      maxSize: 0.35,
      minLife: 0.15,
      maxLife: 0.4,
      color1: new BABYLON.Color4(0.5, 1, 1, 1),
      color2: new BABYLON.Color4(0.7, 0.9, 1, 0.8),
      colorDead: new BABYLON.Color4(0.8, 1, 1, 0),
      minPower: 4,
      maxPower: 9,
      gravity: new BABYLON.Vector3(0, -6, 0),
      stopAfterMs: 40,
      disposeAfterMs: 500,
      emitterRadius: 0.4,
    });
    // tracked in createBurst
  }

  /**
   * Ice shatter — big cyan burst with white sparkles.
   */
  public createIceShatterEffect(position: BABYLON.Vector3): void {
    // Main cyan burst
    this.createBurst('iceShatterMain', position, 100, {
      minSize: 0.2,
      maxSize: 0.6,
      minLife: 0.3,
      maxLife: 0.8,
      color1: new BABYLON.Color4(0.4, 0.9, 1, 1),
      color2: new BABYLON.Color4(0.6, 1, 1, 0.9),
      colorDead: new BABYLON.Color4(0.7, 1, 1, 0),
      minPower: 6,
      maxPower: 14,
      gravity: new BABYLON.Vector3(0, -9, 0),
      stopAfterMs: 60,
      disposeAfterMs: 1000,
      emitterRadius: 1.2,
    });
    // tracked in createBurst

    // White sparkles overlay
    this.createBurst('iceShatterSparkles', position, 40, {
      minSize: 0.08,
      maxSize: 0.2,
      minLife: 0.5,
      maxLife: 1.0,
      color1: new BABYLON.Color4(1, 1, 1, 1),
      color2: new BABYLON.Color4(0.8, 1, 1, 0.6),
      colorDead: new BABYLON.Color4(1, 1, 1, 0),
      minPower: 2,
      maxPower: 6,
      gravity: new BABYLON.Vector3(0, -3, 0),
      stopAfterMs: 80,
      disposeAfterMs: 1200,
      emitterRadius: 0.8,
    });
    // tracked in createBurst
  }

  /**
   * Weapon pickup — celebration burst matching weapon color.
   */
  public createWeaponPickupEffect(position: BABYLON.Vector3, color: BABYLON.Color3): void {
    this.createBurst('weaponPickup', position, 60, {
      minSize: 0.2,
      maxSize: 0.5,
      minLife: 0.5,
      maxLife: 1.2,
      color1: new BABYLON.Color4(color.r, color.g, color.b, 1),
      color2: new BABYLON.Color4(1, 1, 0.5, 0.8),
      colorDead: new BABYLON.Color4(color.r * 0.5, color.g * 0.5, color.b * 0.5, 0),
      minPower: 4,
      maxPower: 10,
      gravity: new BABYLON.Vector3(0, -4, 0),
      stopAfterMs: 80,
      disposeAfterMs: 1500,
      emitterRadius: 0.8,
    });
    // tracked in createBurst
  }

  /**
   * Boss death — massive multi-color explosion in staggered waves.
   */
  public createBossDeathEffect(position: BABYLON.Vector3): void {
    const waveColors: Array<[BABYLON.Color4, BABYLON.Color4]> = [
      [new BABYLON.Color4(1, 0.3, 0, 1),    new BABYLON.Color4(1, 0.6, 0, 0.8)],   // Orange
      [new BABYLON.Color4(1, 1, 0, 1),       new BABYLON.Color4(1, 0.8, 0.2, 0.8)], // Yellow
      [new BABYLON.Color4(1, 0.1, 0.1, 1),  new BABYLON.Color4(0.8, 0, 0.2, 0.7)], // Red
      [new BABYLON.Color4(0.5, 0.2, 1, 1),  new BABYLON.Color4(0.8, 0.4, 1, 0.8)], // Purple
    ];

    waveColors.forEach(([c1, c2], index) => {
      setTimeout(() => {
        const offset = new BABYLON.Vector3(
          (Math.random() - 0.5) * 2,
          Math.random() * 2,
          (Math.random() - 0.5) * 2
        );
        this.createBurst(`bossDeath_${index}`, position.add(offset), 120, {
          minSize: 0.3,
          maxSize: 1.0,
          minLife: 0.4,
          maxLife: 1.0,
          color1: c1,
          color2: c2,
          colorDead: new BABYLON.Color4(0.2, 0.1, 0, 0),
          minPower: 8,
          maxPower: 18,
          gravity: new BABYLON.Vector3(0, -6, 0),
          stopAfterMs: 80,
          disposeAfterMs: 1200,
          emitterRadius: 1.5,
        });
        // tracked in createBurst
      }, index * 120);
    });
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  private createBurst(
    name: string,
    position: BABYLON.Vector3,
    particleCount: number,
    options: {
      minSize: number;
      maxSize: number;
      minLife: number;
      maxLife: number;
      color1: BABYLON.Color4;
      color2: BABYLON.Color4;
      colorDead: BABYLON.Color4;
      minPower: number;
      maxPower: number;
      gravity: BABYLON.Vector3;
      stopAfterMs: number;
      disposeAfterMs: number;
      emitterRadius: number;
    }
  ): BABYLON.ParticleSystem | null {
    if (!this.canSpawn()) return null;

    const ps = new BABYLON.ParticleSystem(name, particleCount, this.scene);

    const emitter = BABYLON.MeshBuilder.CreateBox(`${name}_emitter`, { size: 0.1 }, this.scene);
    emitter.position = position.clone();
    emitter.isVisible = false;
    ps.emitter = emitter;

    ps.particleTexture = this.createParticleTexture();
    ps.minSize = options.minSize;
    ps.maxSize = options.maxSize;
    ps.minLifeTime = options.minLife;
    ps.maxLifeTime = options.maxLife;

    ps.color1 = options.color1;
    ps.color2 = options.color2;
    ps.colorDead = options.colorDead;

    ps.emitRate = 0;
    ps.manualEmitCount = particleCount;
    ps.minEmitPower = options.minPower;
    ps.maxEmitPower = options.maxPower;
    ps.updateSpeed = 0.016;

    ps.createSphereEmitter(options.emitterRadius);
    ps.gravity = options.gravity;
    ps.blendMode = BABYLON.ParticleSystem.BLENDMODE_ONEONE;

    ps.start();
    this.activeSystems.push(ps);

    setTimeout(() => {
      ps.stop();
      setTimeout(() => {
        this.disposeSystem(ps, emitter);
      }, options.disposeAfterMs);
    }, options.stopAfterMs);

    return ps;
  }


  private disposeSystem(ps: BABYLON.ParticleSystem, emitter: BABYLON.Mesh): void {
    const index = this.activeSystems.indexOf(ps);
    if (index > -1) this.activeSystems.splice(index, 1);

    ps.dispose();
    emitter.dispose();
  }

  private createParticleTexture(): BABYLON.Texture {
    const size = 64;
    const canvas = document.createElement('canvas');
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext('2d')!;

    const gradient = ctx.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
    gradient.addColorStop(0, 'rgba(255, 255, 255, 1)');
    gradient.addColorStop(0.5, 'rgba(255, 255, 255, 0.5)');
    gradient.addColorStop(1, 'rgba(255, 255, 255, 0)');

    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, size, size);

    const texture = new BABYLON.Texture('data:particleTexture', this.scene, false, false);
    texture.updateURL(canvas.toDataURL());
    return texture;
  }

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  public update(_dt: number): void {
    // Babylon.js particle systems update themselves each frame.
  }

  public destroy(): void {
    this.activeSystems.forEach(ps => {
      ps.stop();
      ps.dispose();
      if (ps.emitter) {
        (ps.emitter as BABYLON.Mesh).dispose();
      }
    });
    this.activeSystems = [];
  }
}
