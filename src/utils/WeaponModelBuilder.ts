import { Scene, Mesh, MeshBuilder, StandardMaterial, Color3 } from '@babylonjs/core';
import { WeaponType } from '@/core/Config';

export class WeaponModelBuilder {
  public static create(scene: Scene, type: WeaponType): Mesh {
    switch (type) {
      case WeaponType.PISTOL: return this.buildPistol(scene);
      case WeaponType.SMG: return this.buildSMG(scene);
      case WeaponType.SHOTGUN: return this.buildShotgun(scene);
      case WeaponType.LASER: return this.buildLaser(scene);
      case WeaponType.ROCKET: return this.buildRocket(scene);
      case WeaponType.MINIGUN: return this.buildMinigun(scene);
      case WeaponType.RAILGUN: return this.buildRailgun(scene);
      case WeaponType.FLAMETHROWER: return this.buildFlamethrower(scene);
    }
  }

  private static buildPistol(scene: Scene): Mesh {
    const mat = this.mat(scene, '#555555', '#333333');
    const barrel = MeshBuilder.CreateCylinder('b', { diameter: 0.08, height: 0.3, tessellation: 6 }, scene);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.z = 0.15;
    barrel.material = mat;

    const grip = MeshBuilder.CreateBox('g', { width: 0.08, height: 0.18, depth: 0.06 }, scene);
    grip.position.set(0, -0.12, -0.02);
    grip.material = mat;

    const body = MeshBuilder.CreateBox('bd', { width: 0.1, height: 0.08, depth: 0.15 }, scene);
    body.position.set(0, 0, -0.02);
    body.material = mat;

    return this.merge(scene, [barrel, grip, body], mat, 'pistol');
  }

  private static buildSMG(scene: Scene): Mesh {
    const mat = this.mat(scene, '#555555', '#8B7500');
    const barrel = MeshBuilder.CreateCylinder('b', { diameter: 0.07, height: 0.5, tessellation: 6 }, scene);
    barrel.rotation.x = Math.PI / 2;
    barrel.position.z = 0.25;
    barrel.material = mat;

    const body = MeshBuilder.CreateBox('bd', { width: 0.1, height: 0.09, depth: 0.25 }, scene);
    body.material = mat;

    const mag = MeshBuilder.CreateBox('m', { width: 0.04, height: 0.14, depth: 0.04 }, scene);
    mag.position.set(0, -0.1, 0.05);
    mag.rotation.z = 0.1;
    mag.material = mat;

    const stock = MeshBuilder.CreateBox('s', { width: 0.06, height: 0.07, depth: 0.1 }, scene);
    stock.position.set(0, 0, -0.17);
    stock.material = mat;

    return this.merge(scene, [barrel, body, mag, stock], mat, 'smg');
  }

  private static buildShotgun(scene: Scene): Mesh {
    const mat = this.mat(scene, '#5C3A1E', '#7A4A00');

    const b1 = MeshBuilder.CreateCylinder('b1', { diameter: 0.06, height: 0.5, tessellation: 6 }, scene);
    b1.rotation.x = Math.PI / 2; b1.position.set(-0.035, 0, 0.25); b1.material = mat;

    const b2 = MeshBuilder.CreateCylinder('b2', { diameter: 0.06, height: 0.5, tessellation: 6 }, scene);
    b2.rotation.x = Math.PI / 2; b2.position.set(0.035, 0, 0.25); b2.material = mat;

    const stock = MeshBuilder.CreateBox('s', { width: 0.09, height: 0.07, depth: 0.25 }, scene);
    stock.position.set(0, 0, -0.12); stock.material = mat;

    const pump = MeshBuilder.CreateBox('p', { width: 0.11, height: 0.05, depth: 0.07 }, scene);
    pump.position.set(0, -0.05, 0.1); pump.material = mat;

    return this.merge(scene, [b1, b2, stock, pump], mat, 'shotgun');
  }

  private static buildLaser(scene: Scene): Mesh {
    const mat = this.mat(scene, '#1E3A5F', '#3B82F6');

    const barrel = MeshBuilder.CreateCylinder('b', { diameter: 0.05, height: 0.6, tessellation: 6 }, scene);
    barrel.rotation.x = Math.PI / 2; barrel.position.z = 0.3; barrel.material = mat;

    const tip = MeshBuilder.CreateSphere('t', { diameter: 0.12, segments: 6 }, scene);
    tip.position.z = 0.6; tip.material = mat;

    const body = MeshBuilder.CreateBox('bd', { width: 0.09, height: 0.07, depth: 0.3 }, scene);
    body.material = mat;

    const lens = MeshBuilder.CreateCylinder('l', { diameter: 0.08, height: 0.03, tessellation: 8 }, scene);
    lens.rotation.x = Math.PI / 2; lens.position.z = 0.56; lens.material = mat;

    return this.merge(scene, [barrel, tip, body, lens], mat, 'laser');
  }

  private static buildRocket(scene: Scene): Mesh {
    const mat = this.mat(scene, '#4A5E3A', '#8B0000');

    const tube = MeshBuilder.CreateCylinder('t', { diameter: 0.16, height: 0.6, tessellation: 8 }, scene);
    tube.rotation.x = Math.PI / 2; tube.position.z = 0.15; tube.material = mat;

    const exhaust = MeshBuilder.CreateCylinder('e', { diameterTop: 0.18, diameterBottom: 0.12, height: 0.1, tessellation: 8 }, scene);
    exhaust.rotation.x = Math.PI / 2; exhaust.position.z = -0.2; exhaust.material = mat;

    const sight = MeshBuilder.CreateBox('s', { width: 0.03, height: 0.08, depth: 0.1 }, scene);
    sight.position.set(0, 0.12, 0.1); sight.material = mat;

    const grip = MeshBuilder.CreateBox('g', { width: 0.06, height: 0.12, depth: 0.06 }, scene);
    grip.position.set(0, -0.12, 0); grip.material = mat;

    return this.merge(scene, [tube, exhaust, sight, grip], mat, 'rocket');
  }

  private static buildMinigun(scene: Scene): Mesh {
    const mat = this.mat(scene, '#555555', '#AAA033');
    // Multi-barrel rotating cluster
    const barrels: Mesh[] = [];
    for (let i = 0; i < 4; i++) {
      const b = MeshBuilder.CreateCylinder(`mb${i}`, { diameter: 0.05, height: 0.55, tessellation: 6 }, scene);
      b.rotation.x = Math.PI / 2;
      const angle = (i / 4) * Math.PI * 2;
      b.position.set(Math.cos(angle) * 0.06, Math.sin(angle) * 0.06, 0.28);
      b.material = mat;
      barrels.push(b);
    }
    const body = MeshBuilder.CreateBox('mgb', { width: 0.14, height: 0.12, depth: 0.25 }, scene);
    body.material = mat;
    const grip = MeshBuilder.CreateBox('mgg', { width: 0.06, height: 0.14, depth: 0.05 }, scene);
    grip.position.set(0, -0.1, -0.05); grip.material = mat;
    return this.merge(scene, [...barrels, body, grip], mat, 'minigun');
  }

  private static buildRailgun(scene: Scene): Mesh {
    const mat = this.mat(scene, '#2D1B69', '#A855F7');
    // Long sleek barrel with coils
    const barrel = MeshBuilder.CreateCylinder('rb', { diameter: 0.06, height: 0.7, tessellation: 6 }, scene);
    barrel.rotation.x = Math.PI / 2; barrel.position.z = 0.35; barrel.material = mat;
    const body = MeshBuilder.CreateBox('rbd', { width: 0.12, height: 0.1, depth: 0.3 }, scene);
    body.material = mat;
    // Coil rings along barrel
    const coils: Mesh[] = [];
    for (let i = 0; i < 3; i++) {
      const coil = MeshBuilder.CreateTorus(`rc${i}`, { diameter: 0.16, thickness: 0.025, tessellation: 8 }, scene);
      coil.rotation.y = Math.PI / 2;
      coil.position.z = 0.15 + i * 0.18;
      coil.material = mat;
      coils.push(coil);
    }
    const tip = MeshBuilder.CreateSphere('rt', { diameter: 0.1, segments: 6 }, scene);
    tip.position.z = 0.7; tip.material = mat;
    return this.merge(scene, [barrel, body, ...coils, tip], mat, 'railgun');
  }

  private static buildFlamethrower(scene: Scene): Mesh {
    const mat = this.mat(scene, '#7C2D12', '#FB923C');
    // Wide nozzle + fuel tank
    const nozzle = MeshBuilder.CreateCylinder('fn', { diameterTop: 0.2, diameterBottom: 0.08, height: 0.4, tessellation: 8 }, scene);
    nozzle.rotation.x = Math.PI / 2; nozzle.position.z = 0.35; nozzle.material = mat;
    const body = MeshBuilder.CreateBox('fb', { width: 0.12, height: 0.1, depth: 0.3 }, scene);
    body.material = mat;
    const tank = MeshBuilder.CreateCylinder('ft', { diameter: 0.14, height: 0.25, tessellation: 6 }, scene);
    tank.position.set(0, -0.08, -0.1); tank.material = mat;
    const grip = MeshBuilder.CreateBox('fg', { width: 0.06, height: 0.12, depth: 0.05 }, scene);
    grip.position.set(0, -0.1, 0.05); grip.material = mat;
    return this.merge(scene, [nozzle, body, tank, grip], mat, 'flamethrower');
  }

  private static mat(scene: Scene, diffuse: string, emissive: string): StandardMaterial {
    const m = new StandardMaterial('weaponMat', scene);
    m.diffuseColor = Color3.FromHexString(diffuse);
    m.emissiveColor = Color3.FromHexString(emissive).scale(0.3);
    m.specularColor = new Color3(0.3, 0.3, 0.3);
    return m;
  }

  private static merge(_scene: Scene, parts: Mesh[], mat: StandardMaterial, name: string): Mesh {
    const merged = Mesh.MergeMeshes(parts, true, false);
    if (merged) {
      merged.name = name;
      merged.material = mat;
      return merged;
    }
    return parts[0];
  }
}
