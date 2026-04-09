import { Config, GameState } from './Config';
import { SceneManager } from './SceneManager';
import { InputHandler } from '@/systems/InputHandler';
import { UIManager } from '@/ui/UIManager';
import { Player } from '@/entities/Player';
import { BulletManager } from '@/systems/BulletManager';
import { EnemyManager } from '@/systems/EnemyManager';
import { CollisionSystem } from '@/systems/CollisionSystem';

export class GameManager {
  private static instance: GameManager;

  private gameState: GameState = GameState.LOADING;
  private distance: number = 0;
  private score: number = 0;
  private kills: number = 0;
  private combo: number = 0;
  private lastFrameTime: number = 0;

  private sceneManager!: SceneManager;
  private inputHandler!: InputHandler;
  private uiManager!: UIManager;
  private player!: Player;
  private bulletManager!: BulletManager;
  private enemyManager!: EnemyManager;
  private collisionSystem!: CollisionSystem;

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

    this.uiManager.onStartGame(() => this.startGame());
    this.uiManager.onRestartGame(() => this.startGame());

    this.gameState = GameState.MENU;
    this.uiManager.showStartScreen();
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP());
  }

  public startGame(): void {
    this.gameState = GameState.PLAYING;
    this.distance = 0;
    this.score = 0;
    this.kills = 0;
    this.combo = 0;
    this.lastFrameTime = performance.now();

    this.player.reset();
    this.bulletManager.clearAll();
    this.enemyManager.clearAll();

    this.uiManager.hideStartScreen();
    this.uiManager.hideGameOver();
    this.uiManager.hideBossHP();
    this.uiManager.hideCombo();
    this.uiManager.updateScore(0);
    this.uiManager.updateDistance(0);
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP());
    this.uiManager.updateWeapon(this.player.getWeaponConfig().name);

    this.gameLoop();
  }

  private gameLoop(): void {
    if (this.gameState !== GameState.PLAYING) return;

    const now = performance.now();
    const dt = (now - this.lastFrameTime) / 1000;
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

    // 2. Player
    this.player.update(dt);

    // 3. Auto-fire
    if (this.player.tryFire()) {
      const weapon = this.player.getWeaponConfig();
      this.bulletManager.fire(this.player.getMuzzlePosition(), weapon);
    }

    // 4. Bullets
    this.bulletManager.update(dt);

    // 5. Enemies
    this.enemyManager.update(dt, this.distance);

    // 6. Bullet → Enemy collisions
    const bullets = this.bulletManager.getActiveBullets();
    const enemies = this.enemyManager.getActiveEnemies();
    const { kills, hits } = this.collisionSystem.checkBulletEnemyCollisions(bullets, enemies);

    for (const kill of kills) {
      this.score += kill.enemy.config.score * Math.max(1, this.combo);
      this.kills++;
      this.combo++;
    }

    if (hits.length > 0 || kills.length > 0) {
      // Keep combo alive on any hit
    }

    // 7. Enemy → Player collisions
    const playerHits = this.collisionSystem.checkEnemyPlayerCollisions(enemies, this.player);
    if (playerHits > 0) {
      this.combo = 0;
      this.uiManager.hideCombo();
    }

    // 8. Update combo display
    if (this.combo >= 3) {
      this.uiManager.showCombo(this.combo);
    }

    // 9. Distance + UI
    this.distance += dt * Config.GAME_SPEED;

    this.uiManager.updateScore(this.score);
    this.uiManager.updateDistance(this.distance);
    this.uiManager.updateHP(this.player.getHP(), this.player.getMaxHP());

    // 10. Game over check
    if (!this.player.isAlive()) {
      this.gameOver();
    }
  }

  private gameOver(): void {
    this.gameState = GameState.GAME_OVER;
    this.uiManager.showGameOver(this.score, this.distance, this.kills);
  }
}
