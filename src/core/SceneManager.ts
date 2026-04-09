import {
  Engine, Scene, ArcRotateCamera, HemisphericLight, DirectionalLight,
  Vector3, Color3, MeshBuilder, StandardMaterial, Color4, DynamicTexture,
} from '@babylonjs/core';
import { Config } from './Config';

export class SceneManager {
  private engine!: Engine;
  private scene!: Scene;
  private camera!: ArcRotateCamera;
  private scrollOffset: number = 0;

  public async initialize(canvas: HTMLCanvasElement): Promise<void> {
    this.engine = new Engine(canvas, true, { preserveDrawingBuffer: true, stencil: true });
    this.scene = new Scene(this.engine);
    this.scene.clearColor = new Color4(0.05, 0.05, 0.12, 1);

    this.createCamera(canvas);
    this.createLighting();
    this.createEnvironment();

    this.engine.runRenderLoop(() => this.scene.render());
    window.addEventListener('resize', () => this.engine.resize());
  }

  private createCamera(canvas: HTMLCanvasElement): void {
    this.camera = new ArcRotateCamera('camera', 0, 0, 10, Vector3.Zero(), this.scene);
    this.camera.setPosition(Config.CAMERA_POSITION);
    this.camera.setTarget(Config.CAMERA_TARGET);
    this.camera.fov = Config.CAMERA_FOV;
    this.camera.attachControl(canvas, false);
    this.camera.inputs.clear();
  }

  private createLighting(): void {
    const hemi = new HemisphericLight('hemi', new Vector3(0, 1, 0), this.scene);
    hemi.intensity = 0.7;
    hemi.groundColor = new Color3(0.2, 0.2, 0.3);

    const sun = new DirectionalLight('sun', new Vector3(-0.3, -1, 0.5), this.scene);
    sun.intensity = 0.5;
    sun.diffuse = new Color3(1, 0.95, 0.85);
  }

  private createEnvironment(): void {
    // Ground
    const ground = MeshBuilder.CreateGround('ground', { width: 120, height: 300 }, this.scene);
    ground.position.set(0, -0.1, 75);
    const groundMat = new StandardMaterial('groundMat', this.scene);
    groundMat.diffuseColor = Color3.FromHexString(Config.COLORS.GROUND);
    groundMat.specularColor = Color3.Black();
    ground.material = groundMat;
    ground.freezeWorldMatrix();
    groundMat.freeze();

    // Road with scrolling texture
    const road = MeshBuilder.CreateGround('road', { width: Config.ROAD_WIDTH, height: 300 }, this.scene);
    road.position.set(0, 0, 75);
    const roadMat = new StandardMaterial('roadMat', this.scene);
    roadMat.specularColor = Color3.Black();

    const roadTex = new DynamicTexture('roadTex', { width: 512, height: 1024 }, this.scene);
    const ctx = roadTex.getContext() as CanvasRenderingContext2D;
    ctx.fillStyle = Config.COLORS.ROAD;
    ctx.fillRect(0, 0, 512, 1024);
    ctx.strokeStyle = '#FFFFFF';
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.moveTo(8, 0); ctx.lineTo(8, 1024);
    ctx.moveTo(504, 0); ctx.lineTo(504, 1024);
    ctx.stroke();
    ctx.strokeStyle = 'rgba(255,255,255,0.4)';
    ctx.lineWidth = 3;
    ctx.setLineDash([40, 30]);
    ctx.beginPath();
    ctx.moveTo(170, 0); ctx.lineTo(170, 1024);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(342, 0); ctx.lineTo(342, 1024);
    ctx.stroke();
    roadTex.update();

    roadMat.diffuseTexture = roadTex;
    roadTex.uScale = 1;
    roadTex.vScale = 8;
    road.material = roadMat;

    this.scene.registerBeforeRender(() => {
      this.scrollOffset += 0.002 * Config.GAME_SPEED;
      roadTex.vOffset = this.scrollOffset;
    });

    // Curbs
    const curbMat = new StandardMaterial('curbMat', this.scene);
    curbMat.diffuseColor = new Color3(0.4, 0.4, 0.4);
    curbMat.specularColor = Color3.Black();
    curbMat.freeze();
    const half = Config.ROAD_WIDTH / 2;
    for (const side of [-1, 1]) {
      const curb = MeshBuilder.CreateBox(`curb${side}`, { width: 0.4, height: 0.3, depth: 300 }, this.scene);
      curb.position.set(side * (half + 0.2), 0.05, 75);
      curb.material = curbMat;
      curb.freezeWorldMatrix();
      curb.isPickable = false;
    }

    // Trees
    this.createTrees();
  }

  private createTrees(): void {
    const trunkMat = new StandardMaterial('trunkMat', this.scene);
    trunkMat.diffuseColor = new Color3(0.35, 0.22, 0.1);
    trunkMat.specularColor = Color3.Black();
    trunkMat.freeze();

    const leafMat = new StandardMaterial('leafMat', this.scene);
    leafMat.diffuseColor = new Color3(0.15, 0.45, 0.1);
    leafMat.specularColor = Color3.Black();
    leafMat.freeze();

    const trunk = MeshBuilder.CreateCylinder('trunkT', { diameter: 0.6, height: 2, tessellation: 6 }, this.scene);
    trunk.material = trunkMat;
    trunk.setEnabled(false);

    const canopy = MeshBuilder.CreateCylinder('canopyT', { diameterTop: 0, diameterBottom: 2.5, height: 3, tessellation: 6 }, this.scene);
    canopy.material = leafMat;
    canopy.setEnabled(false);

    const half = Config.ROAD_WIDTH / 2 + 3;
    for (let z = -10; z < 150; z += 7) {
      for (const side of [-1, 1]) {
        if (Math.random() > 0.65) continue;
        const x = side * (half + 3 + Math.random() * 8);
        const zj = z + (Math.random() - 0.5) * 4;
        const t = trunk.createInstance(`t_${z}_${side}`);
        t.position.set(x, 1, zj);
        t.freezeWorldMatrix();
        t.isPickable = false;
        const c = canopy.createInstance(`c_${z}_${side}`);
        const s = 0.8 + Math.random() * 0.4;
        c.scaling.setAll(s);
        c.position.set(x, 3.2, zj);
        c.freezeWorldMatrix();
        c.isPickable = false;
      }
    }
  }

  public getScene(): Scene { return this.scene; }
  public getCamera(): ArcRotateCamera { return this.camera; }
  public dispose(): void { this.scene.dispose(); this.engine.dispose(); }
}
