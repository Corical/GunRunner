import * as BABYLON from '@babylonjs/core';

/**
 * Manages camera effects: screen shake, FOV zoom, and smooth transitions.
 */
export class CameraEffects {
  private camera: BABYLON.ArcRotateCamera;
  private basePosition: BABYLON.Vector3;
  private baseTarget: BABYLON.Vector3;
  private baseFOV: number;

  // Screen shake state
  private shakeIntensity: number = 0;
  private shakeDuration: number = 0;
  private shakeTimer: number = 0;

  // Dynamic zoom state
  private targetFOV: number;
  private readonly fovTransitionSpeed: number = 2.0;

  // Camera target smoothing
  private targetOffset: BABYLON.Vector3;
  private readonly smoothSpeed: number = 3.0;

  constructor(camera: BABYLON.ArcRotateCamera) {
    this.camera = camera;
    this.basePosition = camera.position.clone();
    this.baseTarget = camera.target.clone();
    this.baseFOV = camera.fov;
    this.targetFOV = camera.fov;
    this.targetOffset = BABYLON.Vector3.Zero();
  }

  /**
   * Trigger a screen shake.
   * @param intensity - Shake strength 0–1
   * @param duration  - Duration in seconds
   */
  public shake(intensity: number = 0.5, duration: number = 0.3): void {
    this.shakeIntensity = Math.min(1, intensity);
    this.shakeDuration = duration;
    this.shakeTimer = 0;
  }

  public shakeLight(): void {
    this.shake(0.3, 0.2);
  }

  public shakeMedium(): void {
    this.shake(0.5, 0.3);
  }

  public shakeHeavy(): void {
    this.shake(0.8, 0.5);
  }

  /**
   * Temporarily change the camera FOV.
   * @param fovMultiplier - < 1 zooms in, > 1 zooms out
   * @param duration      - Duration in seconds before returning to base FOV
   */
  public zoom(fovMultiplier: number, duration: number = 0.5): void {
    this.targetFOV = this.baseFOV * fovMultiplier;

    setTimeout(() => {
      this.targetFOV = this.baseFOV;
    }, duration * 1000);
  }

  public zoomIn(amount: number = 0.8): void {
    this.zoom(amount, 0.5);
  }

  public zoomOut(amount: number = 1.2): void {
    this.zoom(amount, 0.5);
  }

  /**
   * Reset all camera effects to default state.
   */
  public reset(): void {
    this.shakeIntensity = 0;
    this.shakeTimer = 0;
    this.targetFOV = this.baseFOV;
    this.targetOffset = BABYLON.Vector3.Zero();
    this.camera.fov = this.baseFOV;
    this.camera.position.copyFrom(this.basePosition);
    this.camera.target.copyFrom(this.baseTarget);
  }

  public update(deltaTime: number): void {
    let offsetX = 0;
    let offsetY = 0;
    let offsetZ = 0;

    // Apply and decay screen shake
    if (this.shakeTimer < this.shakeDuration) {
      this.shakeTimer += deltaTime;
      const progress = this.shakeTimer / this.shakeDuration;
      const currentIntensity = this.shakeIntensity * (1 - progress);

      offsetX = (Math.random() - 0.5) * currentIntensity * 2;
      offsetY = (Math.random() - 0.5) * currentIntensity * 2;
      offsetZ = (Math.random() - 0.5) * currentIntensity * 1;
    }

    // Smooth FOV transition toward target
    const fovDiff = this.targetFOV - this.camera.fov;
    if (Math.abs(fovDiff) > 0.001) {
      this.camera.fov += fovDiff * this.fovTransitionSpeed * deltaTime;
    }

    // Smooth target offset transition
    const targetDiff = this.targetOffset.subtract(BABYLON.Vector3.Zero());
    if (targetDiff.length() > 0.01) {
      const smoothOffset = BABYLON.Vector3.Lerp(
        BABYLON.Vector3.Zero(),
        this.targetOffset,
        this.smoothSpeed * deltaTime
      );
      this.camera.target.x = this.baseTarget.x + smoothOffset.x;
    } else {
      this.camera.target.x = this.baseTarget.x;
    }

    // Apply shake offsets to camera position
    this.camera.position.x = this.basePosition.x + offsetX;
    this.camera.position.y = this.basePosition.y + offsetY;
    this.camera.position.z = this.basePosition.z + offsetZ;

    // Keep target vertically stable when not shaking
    if (this.shakeTimer >= this.shakeDuration) {
      this.camera.target.y = this.baseTarget.y + offsetY * 0.5;
    }
  }

  public destroy(): void {
    this.reset();
  }
}
