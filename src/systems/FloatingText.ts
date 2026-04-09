import * as BABYLON from '@babylonjs/core';

/**
 * Internal representation of a single floating text element.
 */
class FloatingTextInstance {
  public mesh: BABYLON.Mesh;
  public velocity: BABYLON.Vector3;
  public lifetime: number;
  public age: number = 0;
  public fadeStart: number;

  constructor(
    mesh: BABYLON.Mesh,
    velocity: BABYLON.Vector3,
    lifetime: number,
    fadeStart: number
  ) {
    this.mesh = mesh;
    this.velocity = velocity;
    this.lifetime = lifetime;
    this.fadeStart = fadeStart;
  }
}

/**
 * Renders animated floating text above world positions.
 * Used for damage numbers, pickups, combos, and milestone messages.
 */
export class FloatingTextSystem {
  private scene: BABYLON.Scene;
  private instances: FloatingTextInstance[] = [];

  constructor(scene: BABYLON.Scene) {
    this.scene = scene;
  }

  /**
   * Spawn a floating text label at the given world position.
   * @param text     - String to display
   * @param position - World-space spawn position
   * @param color    - Text fill color
   * @param scale    - Mesh size multiplier
   */
  public showFloatingText(
    text: string,
    position: BABYLON.Vector3,
    color: BABYLON.Color3 = BABYLON.Color3.Green(),
    scale: number = 1.0
  ): void {
    const texWidth = 1024;
    const texHeight = 256;
    const texture = new BABYLON.DynamicTexture(
      'floatingText',
      { width: texWidth, height: texHeight },
      this.scene,
      false
    );

    const ctx = texture.getContext() as CanvasRenderingContext2D;
    ctx.clearRect(0, 0, texWidth, texHeight);

    // Auto-size font to fit canvas width
    let fontSize = 120;
    ctx.font = `bold ${fontSize}px Arial`;
    let textWidth = ctx.measureText(text).width;
    while (textWidth > texWidth * 0.9 && fontSize > 40) {
      fontSize -= 10;
      ctx.font = `bold ${fontSize}px Arial`;
      textWidth = ctx.measureText(text).width;
    }

    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Black outline for readability
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.8)';
    ctx.lineWidth = 8;
    ctx.strokeText(text, texWidth / 2, texHeight / 2);

    // Colored fill
    ctx.fillStyle = color.toHexString();
    ctx.fillText(text, texWidth / 2, texHeight / 2);

    texture.update();

    const plane = BABYLON.MeshBuilder.CreatePlane(
      'floatingTextPlane',
      { width: 4 * scale, height: 2 * scale },
      this.scene
    );

    plane.position = position.clone();
    plane.position.y = Math.max(position.y, 3) + 2; // Always render above ground/road
    plane.billboardMode = BABYLON.Mesh.BILLBOARDMODE_ALL;

    // Render above scene geometry so ground/road never clips text
    plane.renderingGroupId = 1;

    const material = new BABYLON.StandardMaterial('floatingTextMat', this.scene);
    material.diffuseTexture = texture;
    material.emissiveTexture = texture;
    material.opacityTexture = texture;
    material.backFaceCulling = false;
    material.disableLighting = true;
    material.useAlphaFromDiffuseTexture = true;
    plane.material = material;

    const velocity = new BABYLON.Vector3(
      (Math.random() - 0.5) * 0.5,
      3 + Math.random() * 2,
      (Math.random() - 0.5) * 0.5
    );

    this.instances.push(
      new FloatingTextInstance(plane, velocity, 2.0, 1.0)
    );
  }

  /** Show a green "+N" gain label. */
  public showGain(amount: number, position: BABYLON.Vector3, scale: number = 1.0): void {
    this.showFloatingText(
      `+${amount}`,
      position,
      BABYLON.Color3.FromHexString('#48BB78'),
      scale
    );
  }

  /** Show a red "-N" loss label. */
  public showLoss(amount: number, position: BABYLON.Vector3): void {
    this.showFloatingText(
      `-${amount}`,
      position,
      BABYLON.Color3.FromHexString('#EF4444')
    );
  }

  /** Show a blue "xN" multiplier label. */
  public showMultiplier(value: number, position: BABYLON.Vector3): void {
    this.showFloatingText(
      `x${value}`,
      position,
      BABYLON.Color3.FromHexString('#3B82F6'),
      1.3
    );
  }

  /** Show an amber combo label (e.g. "5x GREAT!"). */
  public showCombo(combo: number, tier: string, position: BABYLON.Vector3): void {
    this.showFloatingText(
      `${combo}x ${tier}!`,
      position,
      BABYLON.Color3.FromHexString('#F59E0B'),
      1.5
    );
  }

  /** Show a purple power-up activation label. */
  public showPowerUpActivated(name: string, position: BABYLON.Vector3): void {
    this.showFloatingText(
      name,
      position,
      BABYLON.Color3.FromHexString('#8B5CF6'),
      1.2
    );
  }

  /** Show a gold milestone label. */
  public showMilestone(text: string, position: BABYLON.Vector3): void {
    this.showFloatingText(
      text,
      position,
      BABYLON.Color3.FromHexString('#FBBF24'),
      1.8
    );
  }

  public update(deltaTime: number): void {
    const toRemove: FloatingTextInstance[] = [];

    this.instances.forEach(instance => {
      instance.age += deltaTime;

      // Drift upward
      instance.mesh.position.addInPlace(instance.velocity.scale(deltaTime));

      // Apply light gravity to upward drift
      instance.velocity.y -= 5 * deltaTime;

      // Fade out during the tail end of the lifetime
      if (instance.age > instance.fadeStart) {
        const fadeProgress =
          (instance.age - instance.fadeStart) / (instance.lifetime - instance.fadeStart);
        const alpha = 1 - fadeProgress;

        if (instance.mesh.material instanceof BABYLON.StandardMaterial) {
          instance.mesh.material.alpha = Math.max(0, alpha);
        }
      }

      // Pop-in scale: 1.3 → 1.0 over the first 0.3 s
      const scaleProgress = Math.min(instance.age / 0.3, 1);
      const s = 1.3 - scaleProgress * 0.3;
      instance.mesh.scaling.set(s, s, s);

      if (instance.age >= instance.lifetime) {
        toRemove.push(instance);
      }
    });

    toRemove.forEach(instance => {
      const index = this.instances.indexOf(instance);
      if (index > -1) this.instances.splice(index, 1);

      if (instance.mesh.material) instance.mesh.material.dispose();
      instance.mesh.dispose();
    });
  }

  public destroy(): void {
    this.instances.forEach(instance => {
      if (instance.mesh.material) instance.mesh.material.dispose();
      instance.mesh.dispose();
    });
    this.instances = [];
  }
}
