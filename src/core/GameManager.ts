import * as BABYLON from '@babylonjs/core';
import { Config, GameState, WeaponType } from './Config';
import { SceneManager } from './SceneManager';
import { InputHandler } from '@/systems/InputHandler';
import { UIManager } from '@/ui/UIManager';
import { Player } from '@/entities/Player';
import { BulletManager } from '@/systems/BulletManager';
import { EnemyManager } from '@/systems/EnemyManager';
import { CollisionSystem } from '@/systems/CollisionSystem';
import { FrozenUpgradeManager } from '@/systems/FrozenUpgradeManager';
import { Boss } from '@/entities/Boss';
import { SoundSystem, SoundType } from '@/systems/SoundSystem';
import { ParticleSystem } from '@/systems/ParticleSystem';
import { CameraEffects } from '@/systems/CameraEffects';
import { FloatingTextSystem } from '@/systems/FloatingText';

export class GameManager {
  private static instance: GameManager;

  private gameState: GameState = GameState.LOADING;
  private distance: number = 0;
  private score: number = 0;
  private kills: number = 0;
  private combo: number = 0;
  private lastFrameTime: number = 0;

  // Boss tracking
  private bossWave: number = 0;
  private bossActive: boolean = false;

  // Manual overrides from settings sliders
  private speedMultiplier: number = 1.0;

  // Core systems
  private sceneManager!: SceneManager;
  private inputHandler!: InputHandler;
  private uiManager!: UIManager;
  private player!: Player;
  private bulletManager!: BulletManager;
  private enemyManager!: EnemyManager;
  private collisionSystem!: CollisionSystem;
  private frozenUpgradeManager!: FrozenUpgradeManager;
  private boss!: Boss;

  // Juice systems
  private soundSystem!: SoundSystem;
  private particleSystem!: ParticleSystem;
  private cameraEffects!: CameraEffects;
  private floatingText!: FloatingTextSystem;

  private constructor() {}

  public static getInstance(): GameManager {
    if (!GameManager.instance) GameManager.instance = new GameManager();
    return GameManager.instance;
  }

  public async initialize(canvas: HTMLCanvasElement): Promise<void> {
    this.sceneManager = new SceneManager();
    this.inputHandler = new InputHandler();
    this.uiManager = new UIManager();

    await this.sceneManager.initialize(canvas);
    this.inputHandler.initialize();
    this.uiManager.initialize();

    const scene = this.sceneManager.getScene();

    this.player = new Player(scene);
    this.bulletManager = new BulletManager(scene);
    this.enemyManager = new EnemyManager(scene);
    this.collisionSystem = new CollisionSystem();
    this.frozenUpgradeManager = new FrozenUpgradeManager(scene);
    this.boss = new Boss(scene);

    // Juice
    this.soundSystem = new SoundSystem(scene);
    this.particleSystem = new ParticleSystem(scene);
    this.cameraEffects = new CameraEffects(
      this.sceneManager.getCamera() as BABYLON.ArcRotateCamera
    );
    this.floatingText = new FloatingTextSystem(scene);

    this.uiManager.onStartGame(() => this.startGame());
    this.uiManager.onRestartGame(() => this.startGame());
    this.uiManager.onSpeedChange((speed) => { this.speedMultiplier = speed; });
    this.uiManager.onSpawnRateChange((interval) => {
      this.enemyManager.setSpawnInterval(interval);
    });

    // Up/Down arrow speed adjustment
    this.inputHandler.onSpeedChange((delta) => {
      this.speedMultiplier = Math.max(0.3, Math.min(3.0, this.speedMultiplier + delta));
    });

    this.gameState = GameState.MENU;
    this.uiManager.showStartScreen();
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP(), this.player.getArmor());
  }

  public startGame(): void {
    this.gameState = GameState.PLAYING;
    this.distance = 0;
    this.score = 0;
    this.kills = 0;
    this.combo = 0;
    this.bossWave = 0;
    this.bossActive = false;
    this.lastFrameTime = performance.now();

    this.player.reset();
    this.bulletManager.clearAll();
    this.enemyManager.clearAll();
    this.frozenUpgradeManager.clearAll();
    this.boss.deactivate();
    this.cameraEffects.reset();

    this.uiManager.hideStartScreen();
    this.uiManager.hideGameOver();
    this.uiManager.hideBossHP();
    this.uiManager.hideCombo();
    this.uiManager.updateScore(0);
    this.uiManager.updateDistance(0);
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP(), this.player.getArmor());
    this.uiManager.updateWeapon(this.player.getWeaponConfig().name);

    this.gameLoop();
  }

  private gameLoop(): void {
    if (this.gameState !== GameState.PLAYING) return;

    const now = performance.now();
    const dt = Math.min((now - this.lastFrameTime) / 1000, 0.05); // Cap at 50ms
    this.lastFrameTime = now;

    try {
      this.update(dt);
    } catch (error) {
      console.error('Game loop error:', error);
    }

    requestAnimationFrame(() => this.gameLoop());
  }

  private update(dt: number): void {
    // 1. Input
    const dir = this.inputHandler.getInputDirection();
    if (dir !== 0) this.player.switchLane(dir);

    // Apply speed multiplier
    const adjustedDt = dt * this.speedMultiplier;

    // 2. Player
    this.player.update(adjustedDt);

    // 3. Auto-fire — apply frenzy damage multiplier
    if (this.player.tryFire()) {
      const weapon = this.player.getWeaponConfig();
      const wType = this.player.getWeaponType();
      const dmgMult = this.player.getDamageMultiplier();
      if (dmgMult !== 1) {
        const boosted = { ...weapon, damage: Math.ceil(weapon.damage * dmgMult) };
        this.bulletManager.fire(this.player.getMuzzlePosition(), boosted, wType);
      } else {
        this.bulletManager.fire(this.player.getMuzzlePosition(), weapon, wType);
      }
      this.soundSystem.playSound(SoundType.SHOOT);
      this.particleSystem.createMuzzleFlash(this.player.getMuzzlePosition());
    }

    // 4. Bullets
    this.bulletManager.update(adjustedDt);

    // 5. Enemies — always update (move + despawn), spawning paused during boss
    this.enemyManager.update(adjustedDt, this.distance);

    // 6. Bullet → Enemy collisions
    const bullets = this.bulletManager.getActiveBullets();
    const enemies = this.enemyManager.getActiveEnemies();
    const { kills, hits } = this.collisionSystem.checkBulletEnemyCollisions(bullets, enemies);

    for (const hit of hits) {
      this.soundSystem.playSound(SoundType.ENEMY_HIT);
      this.particleSystem.createEnemyHitEffect(
        new BABYLON.Vector3(hit.position.x, hit.position.y, hit.position.z)
      );
      this.floatingText.showLoss(hit.damage,
        new BABYLON.Vector3(hit.position.x, hit.position.y + 1, hit.position.z)
      );
    }

    for (const kill of kills) {
      this.score += kill.enemy.config.score * Math.max(1, this.combo);
      this.kills++;
      this.combo++;

      this.soundSystem.playSound(SoundType.ENEMY_KILL);
      const kp = new BABYLON.Vector3(kill.position.x, kill.position.y, kill.position.z);
      this.particleSystem.createEnemyDeathEffect(
        kp, BABYLON.Color3.FromHexString(kill.enemy.config.color)
      );
      this.floatingText.showGain(kill.enemy.config.score,
        new BABYLON.Vector3(kp.x, kp.y + 1.5, kp.z)
      );
    }

    // 7. Boss — charges at player, bullets damage it, contact = heavy damage
    if (this.bossActive && this.boss.active) {
      this.boss.update(adjustedDt);

      // Bullets hit boss
      for (const bullet of bullets) {
        if (!bullet.active) continue;
        const dx = bullet.position.x - this.boss.position.x;
        const dz = bullet.position.z - this.boss.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        if (dist < Config.BULLET_HIT_RADIUS + this.boss.getCollisionRadius()) {
          const defeated = this.boss.takeDamage(bullet.damage);
          const shouldDeactivate = bullet.onHit();
          if (shouldDeactivate) bullet.deactivate();

          this.soundSystem.playSound(SoundType.ENEMY_HIT);
          this.particleSystem.createEnemyHitEffect(
            new BABYLON.Vector3(bullet.position.x, 2, bullet.position.z)
          );
          this.uiManager.updateBossHP(this.boss.hp, this.boss.maxHp);

          if (defeated) {
            this.onBossDefeated();
            break;
          }
        }
      }

      // Boss reaches player — heavy contact damage
      if (this.boss.active) {
        const playerPos = this.player.getPosition();
        if (this.boss.checkPlayerContact(playerPos.x, playerPos.z, 1.0)) {
          this.player.takeDamage(3);
          this.soundSystem.playSound(SoundType.PLAYER_HIT);
          this.cameraEffects.shakeHeavy();
          // Push boss back slightly so it doesn't instakill
          this.boss.position.z += 8;
        }
      }
    }

    // 8. Frozen upgrade spawn + update
    if (!this.bossActive && Math.random() < Config.FROZEN_SPAWN_CHANCE) {
      this.frozenUpgradeManager.spawnUpgrade();
    }
    this.frozenUpgradeManager.update(adjustedDt);

    // 9. Bullet → Frozen collisions
    const activeUpgrades = this.frozenUpgradeManager.getActiveUpgrades();
    const frozenPositions = activeUpgrades.map(u => u.getCollisionInfo());
    this.collisionSystem.checkBulletFrozenCollisions(bullets, frozenPositions, (index, damage) => {
      const thawed = activeUpgrades[index].takeDamage(damage);
      this.soundSystem.playSound(thawed ? SoundType.ICE_SHATTER : SoundType.ICE_CRACK);
      if (thawed) {
        this.particleSystem.createIceShatterEffect(activeUpgrades[index].position.clone());
      } else {
        this.particleSystem.createIceCrackEffect(activeUpgrades[index].position.clone());
      }
    });

    // 10. Thawed upgrade pickup
    const playerLane = this.player.getCurrentLane();
    for (const upgrade of activeUpgrades) {
      if (!upgrade.thawed || upgrade.collected) continue;
      if (upgrade.lane === playerLane) {
        const dz = Math.abs(upgrade.position.z - this.player.getPosition().z);
        if (dz < 2.5) {
          upgrade.collected = true;
          upgrade.deactivate();

          this.soundSystem.playSound(SoundType.WEAPON_PICKUP);
          this.particleSystem.createWeaponPickupEffect(
            upgrade.position.clone(), BABYLON.Color3.Yellow()
          );

          const pos = upgrade.position.clone();
          switch (upgrade.reward) {
            case 'heal':
              this.player.heal(2);
              this.floatingText.showPowerUpActivated('+2 HP!', pos);
              break;
            case 'armor':
              this.player.addArmor(3);
              this.floatingText.showPowerUpActivated('+3 ARMOR!', pos);
              break;
            case 'maxhp':
              this.player.addMaxHP(1);
              this.floatingText.showPowerUpActivated('MAX HP UP!', pos);
              break;
            case 'frenzy':
              this.player.activateFrenzy(8);
              this.floatingText.showPowerUpActivated('FRENZY! 8s', pos);
              break;
            case 'speed':
              this.player.activateSpeedBoost(10);
              this.floatingText.showPowerUpActivated('FIRE RATE! 10s', pos);
              break;
            default:
              this.player.setWeapon(upgrade.reward as WeaponType);
              this.uiManager.updateWeapon(this.player.getWeaponConfig().name);
              this.floatingText.showPowerUpActivated(
                this.player.getWeaponConfig().name.toUpperCase() + '!', pos
              );
          }

          this.cameraEffects.zoomIn(0.9);
        }
      }
    }

    // 11. Enemy → Player collisions
    const playerHits = this.collisionSystem.checkEnemyPlayerCollisions(enemies, this.player);
    if (playerHits > 0) {
      this.combo = 0;
      this.uiManager.hideCombo();
      this.soundSystem.playSound(SoundType.PLAYER_HIT);
      this.cameraEffects.shakeMedium();
    }

    // 12. Combo display
    if (this.combo >= 3) {
      this.uiManager.showCombo(this.combo);
    } else {
      this.uiManager.hideCombo();
    }

    // 13. Boss spawn check
    if (!this.bossActive) {
      const nextBossDist = (this.bossWave + 1) * Config.BOSS_INTERVAL_DISTANCE;
      if (this.distance >= nextBossDist) {
        this.startBoss();
      }
    }

    // 14. Distance + UI
    this.distance += adjustedDt * Config.GAME_SPEED;

    this.uiManager.updateScore(this.score);
    this.uiManager.updateDistance(this.distance);
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP(), this.player.getArmor());

    // Juice updates
    this.cameraEffects.update(dt);
    this.floatingText.update(dt);

    // 15. Game over check
    if (!this.player.isAlive()) {
      this.gameOver();
    }
  }

  private startBoss(): void {
    this.bossWave++;
    this.bossActive = true;
    this.enemyManager.pauseSpawning();

    const bossHp = Config.BOSS_BASE_HP + Config.BOSS_HP_SCALE_PER_WAVE * this.bossWave;
    this.boss.activate(bossHp);

    this.soundSystem.playSound(SoundType.BOSS_INTRO);
    this.cameraEffects.shakeHeavy();
    this.floatingText.showMilestone('BOSS INCOMING!', this.player.getPosition().add(new BABYLON.Vector3(0, 5, 0)));
    this.uiManager.showBossHP(`BOSS WAVE ${this.bossWave}`, bossHp, bossHp);
  }

  private onBossDefeated(): void {
    this.bossActive = false;
    this.enemyManager.resumeSpawning();

    this.soundSystem.playSound(SoundType.ENEMY_KILL);
    this.particleSystem.createBossDeathEffect(this.boss.position.clone());
    this.cameraEffects.shakeHeavy();
    this.floatingText.showMilestone('BOSS DEFEATED!', this.boss.position.add(new BABYLON.Vector3(0, 4, 0)));
    this.uiManager.hideBossHP();

    // Guaranteed weapon drop
    this.frozenUpgradeManager.spawnUpgrade();

    this.score += 500 * this.bossWave;
  }

  private gameOver(): void {
    this.gameState = GameState.GAME_OVER;
    this.soundSystem.playSound(SoundType.GAME_OVER);
    this.cameraEffects.shakeHeavy();
    this.uiManager.showGameOver(this.score, this.distance, this.kills);
  }
}
