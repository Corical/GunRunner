import { Vector3 } from '@babylonjs/core';

export const Config = {
  // Game
  GAME_SPEED: 12,
  LANE_WIDTH: 5,
  ROAD_WIDTH: 15,
  INITIAL_HP: 5,
  MAX_HP: 8,

  // Lanes
  LANES: { LEFT: -5, CENTER: 0, RIGHT: 5 },

  // Player
  PLAYER_LANE_SWITCH_DURATION: 0.2,
  PLAYER_HEIGHT: 0.5,
  PLAYER_Z_POSITION: -8,

  // Enemies
  ENEMY_SPAWN_INTERVAL: 1.8,
  ENEMY_SPAWN_DISTANCE: 120,
  ENEMY_SPEED: 10,
  ENEMY_DESPAWN_Z: -15,
  MAX_ENEMIES_ON_SCREEN: 20,

  // Bullets
  BULLET_SPEED: 60,
  BULLET_DESPAWN_Z: 130,

  // Frozen upgrades
  FROZEN_SPAWN_CHANCE: 0.008, // per frame chance
  FROZEN_ICE_HP: 8,
  FROZEN_SPEED: 6,

  // Boss
  BOSS_INTERVAL_DISTANCE: 500, // boss every 500m
  BOSS_BASE_HP: 50,
  BOSS_HP_SCALE_PER_WAVE: 20,

  // Camera
  CAMERA_POSITION: new Vector3(0, 18, -22),
  CAMERA_TARGET: new Vector3(0, 0, 8),
  CAMERA_FOV: 0.8,

  // Collision
  BULLET_HIT_RADIUS: 1.2,
  ENEMY_HIT_PLAYER_RADIUS: 1.5,

  // Rendering
  TARGET_FPS: 60,

  // Colors
  COLORS: {
    PLAYER: '#3B82F6',
    BULLET: '#FBBF24',
    ENEMY_BASIC: '#EF4444',
    ENEMY_ARMORED: '#7C3AED',
    ENEMY_FAST: '#F97316',
    ENEMY_SHIELDED: '#6B7280',
    BOSS: '#DC2626',
    FROZEN_ICE: '#67E8F9',
    ROAD: '#555555',
    GROUND: '#2D5A27',
    HP_FULL: '#22C55E',
    HP_LOW: '#EF4444',
  },
} as const;

export enum GameState {
  LOADING = 'LOADING',
  MENU = 'MENU',
  PLAYING = 'PLAYING',
  PAUSED = 'PAUSED',
  GAME_OVER = 'GAME_OVER',
  BOSS_INTRO = 'BOSS_INTRO',
}

export enum Lane {
  LEFT = -1,
  CENTER = 0,
  RIGHT = 1,
}

export enum LaneDirection {
  LEFT = -1,
  NONE = 0,
  RIGHT = 1,
}

export enum WeaponType {
  PISTOL = 'pistol',
  SMG = 'smg',
  SHOTGUN = 'shotgun',
  LASER = 'laser',
  ROCKET = 'rocket',
}

export enum EnemyType {
  BASIC = 'basic',
  ARMORED = 'armored',
  FAST = 'fast',
  SHIELDED = 'shielded',
}

export interface WeaponConfig {
  name: string;
  fireRate: number;      // shots per second
  damage: number;
  bulletCount: number;    // 1 for single, 3 for shotgun spread
  bulletSpread: number;   // lateral spread in units
  bulletColor: string;
  bulletSize: number;
}

export const WEAPONS: Record<WeaponType, WeaponConfig> = {
  [WeaponType.PISTOL]: {
    name: 'Pistol',
    fireRate: 3,
    damage: 1,
    bulletCount: 1,
    bulletSpread: 0,
    bulletColor: '#FBBF24',
    bulletSize: 0.2,
  },
  [WeaponType.SMG]: {
    name: 'SMG',
    fireRate: 8,
    damage: 1,
    bulletCount: 1,
    bulletSpread: 0.3,
    bulletColor: '#FCD34D',
    bulletSize: 0.15,
  },
  [WeaponType.SHOTGUN]: {
    name: 'Shotgun',
    fireRate: 2,
    damage: 2,
    bulletCount: 5,
    bulletSpread: 2.0,
    bulletColor: '#F97316',
    bulletSize: 0.18,
  },
  [WeaponType.LASER]: {
    name: 'Laser',
    fireRate: 12,
    damage: 1,
    bulletCount: 1,
    bulletSpread: 0,
    bulletColor: '#60A5FA',
    bulletSize: 0.1,
  },
  [WeaponType.ROCKET]: {
    name: 'Rocket',
    fireRate: 1.5,
    damage: 8,
    bulletCount: 1,
    bulletSpread: 0,
    bulletColor: '#EF4444',
    bulletSize: 0.35,
  },
};

export interface EnemyConfig {
  name: string;
  hp: number;
  speed: number;        // multiplier of ENEMY_SPEED
  color: string;
  size: number;
  score: number;
  switchesLanes: boolean;
}

export const ENEMIES: Record<EnemyType, EnemyConfig> = {
  [EnemyType.BASIC]: {
    name: 'Runner',
    hp: 1,
    speed: 1.0,
    color: Config.COLORS.ENEMY_BASIC,
    size: 1.0,
    score: 10,
    switchesLanes: false,
  },
  [EnemyType.ARMORED]: {
    name: 'Tank',
    hp: 4,
    speed: 0.7,
    color: Config.COLORS.ENEMY_ARMORED,
    size: 1.4,
    score: 30,
    switchesLanes: false,
  },
  [EnemyType.FAST]: {
    name: 'Flanker',
    hp: 1,
    speed: 1.6,
    color: Config.COLORS.ENEMY_FAST,
    size: 0.8,
    score: 20,
    switchesLanes: true,
  },
  [EnemyType.SHIELDED]: {
    name: 'Shield',
    hp: 3,
    speed: 0.8,
    color: Config.COLORS.ENEMY_SHIELDED,
    size: 1.2,
    score: 25,
    switchesLanes: false,
  },
};
