import * as BABYLON from '@babylonjs/core';

export enum SoundType {
  SHOOT = 'shoot',
  ENEMY_HIT = 'enemy_hit',
  ENEMY_KILL = 'enemy_kill',
  PLAYER_HIT = 'player_hit',
  ICE_CRACK = 'ice_crack',
  ICE_SHATTER = 'ice_shatter',
  WEAPON_PICKUP = 'weapon_pickup',
  BOSS_INTRO = 'boss_intro',
  GAME_OVER = 'game_over',
}

/**
 * Manages all sound effects using procedural Web Audio synthesis.
 * No external audio files required.
 */
export class SoundSystem {
  private scene: BABYLON.Scene;
  private sounds: Map<SoundType, BABYLON.Sound> = new Map();
  private isMuted: boolean = false;
  private sfxVolume: number = 0.5;
  private initialized: boolean = false;

  constructor(scene: BABYLON.Scene) {
    this.scene = scene;
    // Defer sound creation — audio context won't exist until user interacts
    this.tryInit();
    // Also try on first user gesture
    const unlock = () => {
      if (!this.initialized) {
        // Unlock BabylonJS audio engine
        if (BABYLON.Engine.audioEngine && !BABYLON.Engine.audioEngine.unlocked) {
          BABYLON.Engine.audioEngine.unlock();
        }
        // Wait a tick for context to be ready, then init
        setTimeout(() => this.tryInit(), 100);
      }
      window.removeEventListener('click', unlock);
      window.removeEventListener('keydown', unlock);
      window.removeEventListener('touchstart', unlock);
    };
    window.addEventListener('click', unlock);
    window.addEventListener('keydown', unlock);
    window.addEventListener('touchstart', unlock);
  }

  private tryInit(): void {
    if (this.initialized) return;
    const ctx = BABYLON.Engine.audioEngine?.audioContext;
    if (!ctx) return;
    // Resume suspended context
    if (ctx.state === 'suspended') {
      ctx.resume();
    }
    this.initializeSounds();
    this.initialized = true;
    console.log('SoundSystem initialized');
  }

  private initializeSounds(): void {
    this.createShootSound();
    this.createEnemyHitSound();
    this.createEnemyKillSound();
    this.createPlayerHitSound();
    this.createIceCrackSound();
    this.createIceShatterSound();
    this.createWeaponPickupSound();
    this.createBossIntroSound();
    this.createGameOverSound();
  }

  /** SHOOT: 0.05s, 1200 Hz sine, fast decay — quick click/pop */
  private createShootSound(): void {
    const sound = this.createOscillatorSound(
      [1200],
      [0.05],
      0.4,
      'sine'
    );
    if (sound) this.sounds.set(SoundType.SHOOT, sound);
  }

  /** ENEMY_HIT: 0.1s noise burst — thud */
  private createEnemyHitSound(): void {
    const sound = this.createNoiseSound(0.1, 0.35, 8);
    if (sound) this.sounds.set(SoundType.ENEMY_HIT, sound);
  }

  /** ENEMY_KILL: 0.15s ascending 440→880 Hz — satisfying crunch */
  private createEnemyKillSound(): void {
    const sound = this.createOscillatorSound(
      [440, 660, 880],
      [0.05, 0.05, 0.05],
      0.45,
      'square'
    );
    if (sound) this.sounds.set(SoundType.ENEMY_KILL, sound);
  }

  /** PLAYER_HIT: 0.2s, 200 Hz buzz — warning */
  private createPlayerHitSound(): void {
    const sound = this.createOscillatorSound(
      [200, 180],
      [0.1, 0.1],
      0.5,
      'sawtooth'
    );
    if (sound) this.sounds.set(SoundType.PLAYER_HIT, sound);
  }

  /** ICE_CRACK: 0.1s, 2000 Hz + noise — sharp crack */
  private createIceCrackSound(): void {
    const sound = this.createMixedSound(2000, 0.1, 0.35, 'sine', 6);
    if (sound) this.sounds.set(SoundType.ICE_CRACK, sound);
  }

  /** ICE_SHATTER: 0.3s, descending 3000→1000 Hz with harmonics — sparkly break */
  private createIceShatterSound(): void {
    const sound = this.createOscillatorSound(
      [3000, 2400, 1800, 1200, 800],
      [0.05, 0.05, 0.06, 0.07, 0.07],
      0.4,
      'sine'
    );
    if (sound) this.sounds.set(SoundType.ICE_SHATTER, sound);
  }

  /** WEAPON_PICKUP: 0.4s, C5 E5 G5 C6 ascending arpeggio — triumphant */
  private createWeaponPickupSound(): void {
    const sound = this.createOscillatorSound(
      [523.25, 659.25, 783.99, 1046.5], // C5, E5, G5, C6
      [0.08, 0.08, 0.1, 0.14],
      0.45,
      'sine'
    );
    if (sound) this.sounds.set(SoundType.WEAPON_PICKUP, sound);
  }

  /** BOSS_INTRO: 0.8s, 80 Hz + 160 Hz low rumble — ominous */
  private createBossIntroSound(): void {
    const sound = this.createOscillatorSound(
      [80, 80, 160, 160, 80],
      [0.15, 0.15, 0.15, 0.15, 0.2],
      0.55,
      'triangle'
    );
    if (sound) this.sounds.set(SoundType.BOSS_INTRO, sound);
  }

  /** GAME_OVER: 0.6s, A4 G4 F4 D4 descending — sad */
  private createGameOverSound(): void {
    const sound = this.createOscillatorSound(
      [440, 392, 349.23, 293.66],
      [0.15, 0.15, 0.15, 0.15],
      0.5,
      'triangle'
    );
    if (sound) this.sounds.set(SoundType.GAME_OVER, sound);
  }

  /**
   * Synthesize a multi-note oscillator sound into a Babylon Sound.
   */
  private createOscillatorSound(
    frequencies: number[],
    durations: number[],
    volume: number,
    waveType: OscillatorType = 'sine'
  ): BABYLON.Sound | null {
    try {
      const audioContext = BABYLON.Engine.audioEngine?.audioContext;
      if (!audioContext) return null;

      const totalDuration = durations.reduce((a, b) => a + b, 0);
      const sampleRate = audioContext.sampleRate;
      const buffer = audioContext.createBuffer(1, Math.ceil(totalDuration * sampleRate), sampleRate);
      const channel = buffer.getChannelData(0);

      let offset = 0;
      frequencies.forEach((freq, index) => {
        const duration = durations[index];
        const samples = Math.ceil(duration * sampleRate);

        for (let i = 0; i < samples; i++) {
          const t = i / sampleRate;
          const envelope = Math.exp(-5 * t / duration);
          channel[offset + i] = this.generateWaveSample(waveType, freq, t) * envelope * volume;
        }
        offset += samples;
      });

      return new BABYLON.Sound(
        `sound_${SoundType}_${Date.now()}`,
        buffer,
        this.scene,
        null,
        { loop: false, autoplay: false, volume: this.sfxVolume }
      );
    } catch (error) {
      console.warn('Could not create oscillator sound:', error);
      return null;
    }
  }

  /**
   * Synthesize a pure noise burst (for hit thuds).
   * decayRate controls how quickly the burst dies (higher = faster).
   */
  private createNoiseSound(
    duration: number,
    volume: number,
    decayRate: number = 10
  ): BABYLON.Sound | null {
    try {
      const audioContext = BABYLON.Engine.audioEngine?.audioContext;
      if (!audioContext) return null;

      const sampleRate = audioContext.sampleRate;
      const buffer = audioContext.createBuffer(1, Math.ceil(duration * sampleRate), sampleRate);
      const channel = buffer.getChannelData(0);

      for (let i = 0; i < buffer.length; i++) {
        const t = i / sampleRate;
        const envelope = Math.exp(-decayRate * t / duration);
        channel[i] = (Math.random() * 2 - 1) * envelope * volume;
      }

      return new BABYLON.Sound(
        `noise_${Date.now()}`,
        buffer,
        this.scene,
        null,
        { loop: false, autoplay: false, volume: this.sfxVolume }
      );
    } catch (error) {
      console.warn('Could not create noise sound:', error);
      return null;
    }
  }

  /**
   * Synthesize a blend of a tone and noise — for cracking sounds.
   */
  private createMixedSound(
    frequency: number,
    duration: number,
    volume: number,
    waveType: OscillatorType,
    noiseDecayRate: number
  ): BABYLON.Sound | null {
    try {
      const audioContext = BABYLON.Engine.audioEngine?.audioContext;
      if (!audioContext) return null;

      const sampleRate = audioContext.sampleRate;
      const samples = Math.ceil(duration * sampleRate);
      const buffer = audioContext.createBuffer(1, samples, sampleRate);
      const channel = buffer.getChannelData(0);

      for (let i = 0; i < samples; i++) {
        const t = i / sampleRate;
        const envelope = Math.exp(-noiseDecayRate * t / duration);
        const tone = this.generateWaveSample(waveType, frequency, t);
        const noise = Math.random() * 2 - 1;
        channel[i] = (tone * 0.5 + noise * 0.5) * envelope * volume;
      }

      return new BABYLON.Sound(
        `mixed_${Date.now()}`,
        buffer,
        this.scene,
        null,
        { loop: false, autoplay: false, volume: this.sfxVolume }
      );
    } catch (error) {
      console.warn('Could not create mixed sound:', error);
      return null;
    }
  }

  private generateWaveSample(waveType: OscillatorType, freq: number, t: number): number {
    switch (waveType) {
      case 'sine':
        return Math.sin(2 * Math.PI * freq * t);
      case 'square':
        return Math.sign(Math.sin(2 * Math.PI * freq * t));
      case 'triangle':
        return 2 * Math.abs(2 * ((freq * t) % 1) - 1) - 1;
      case 'sawtooth':
        return 2 * ((freq * t) % 1) - 1;
      default:
        return Math.sin(2 * Math.PI * freq * t);
    }
  }

  /**
   * Play a specific sound effect. Stops current playback to allow rapid re-triggering.
   */
  public playSound(type: SoundType): void {
    if (this.isMuted) return;

    const sound = this.sounds.get(type);
    if (sound && sound.isReady()) {
      if (sound.isPlaying) sound.stop();
      sound.play();
    }
  }

  public toggleMute(): void {
    this.isMuted = !this.isMuted;

    if (this.isMuted) {
      this.sounds.forEach(sound => {
        if (sound.isPlaying) sound.stop();
      });
    }
  }

  public setSFXVolume(volume: number): void {
    this.sfxVolume = Math.max(0, Math.min(1, volume));
    this.sounds.forEach(sound => sound.setVolume(this.sfxVolume));
  }

  public isSoundMuted(): boolean {
    return this.isMuted;
  }

  public destroy(): void {
    this.sounds.forEach(sound => sound.dispose());
    this.sounds.clear();
  }
}
