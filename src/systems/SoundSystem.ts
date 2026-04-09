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
 * Sound system using raw Web Audio API — bypasses BabylonJS audio entirely.
 * Each sound is synthesized on-the-fly when played.
 */
export class SoundSystem {
  private ctx: AudioContext | null = null;
  private isMuted: boolean = false;
  private volume: number = 0.3;

  constructor(_scene: BABYLON.Scene) {
    // Try to create AudioContext immediately
    this.tryCreateContext();

    // Also try on user gesture (browsers block audio before interaction)
    const unlock = () => {
      this.tryCreateContext();
      if (this.ctx && this.ctx.state === 'suspended') {
        this.ctx.resume();
      }
      window.removeEventListener('click', unlock);
      window.removeEventListener('keydown', unlock);
      window.removeEventListener('touchstart', unlock);
    };
    window.addEventListener('click', unlock);
    window.addEventListener('keydown', unlock);
    window.addEventListener('touchstart', unlock);
  }

  private tryCreateContext(): void {
    if (this.ctx) return;
    try {
      this.ctx = new AudioContext();
    } catch {
      // AudioContext not available
    }
  }

  public playSound(type: SoundType): void {
    if (this.isMuted || !this.ctx) return;

    // Resume if suspended (browser policy)
    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }

    switch (type) {
      case SoundType.SHOOT:       this.playTone(1200, 0.04, 0.25, 'sine'); break;
      case SoundType.ENEMY_HIT:   this.playNoise(0.06, 0.2); break;
      case SoundType.ENEMY_KILL:  this.playChord([440, 660, 880], 0.04, 0.3, 'square'); break;
      case SoundType.PLAYER_HIT:  this.playTone(180, 0.15, 0.4, 'sawtooth'); break;
      case SoundType.ICE_CRACK:   this.playMixed(2000, 0.08, 0.25); break;
      case SoundType.ICE_SHATTER: this.playChord([3000, 2000, 1000], 0.1, 0.3, 'sine'); break;
      case SoundType.WEAPON_PICKUP: this.playChord([523, 659, 784, 1047], 0.08, 0.35, 'sine'); break;
      case SoundType.BOSS_INTRO:  this.playChord([80, 160], 0.4, 0.5, 'triangle'); break;
      case SoundType.GAME_OVER:   this.playChord([440, 392, 349, 294], 0.15, 0.4, 'triangle'); break;
    }
  }

  /** Play a single tone with exponential decay */
  private playTone(freq: number, duration: number, vol: number, type: OscillatorType): void {
    if (!this.ctx) return;
    const osc = this.ctx.createOscillator();
    const gain = this.ctx.createGain();

    osc.type = type;
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(vol * this.volume, this.ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, this.ctx.currentTime + duration);

    osc.connect(gain);
    gain.connect(this.ctx.destination);
    osc.start();
    osc.stop(this.ctx.currentTime + duration + 0.01);
  }

  /** Play a sequence of tones (chord/arpeggio) */
  private playChord(freqs: number[], noteDuration: number, vol: number, type: OscillatorType): void {
    if (!this.ctx) return;
    freqs.forEach((freq, i) => {
      const osc = this.ctx!.createOscillator();
      const gain = this.ctx!.createGain();

      osc.type = type;
      osc.frequency.value = freq;

      const startTime = this.ctx!.currentTime + i * noteDuration;
      gain.gain.setValueAtTime(vol * this.volume, startTime);
      gain.gain.exponentialRampToValueAtTime(0.001, startTime + noteDuration * 1.5);

      osc.connect(gain);
      gain.connect(this.ctx!.destination);
      osc.start(startTime);
      osc.stop(startTime + noteDuration * 2);
    });
  }

  /** Play a noise burst (for impacts) */
  private playNoise(duration: number, vol: number): void {
    if (!this.ctx) return;
    const bufferSize = Math.ceil(this.ctx.sampleRate * duration);
    const buffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = buffer.getChannelData(0);

    for (let i = 0; i < bufferSize; i++) {
      const t = i / this.ctx.sampleRate;
      const envelope = Math.exp(-15 * t / duration);
      data[i] = (Math.random() * 2 - 1) * envelope;
    }

    const source = this.ctx.createBufferSource();
    source.buffer = buffer;
    const gain = this.ctx.createGain();
    gain.gain.value = vol * this.volume;
    source.connect(gain);
    gain.connect(this.ctx.destination);
    source.start();
  }

  /** Play a mix of tone + noise (for cracking sounds) */
  private playMixed(freq: number, duration: number, vol: number): void {
    this.playTone(freq, duration, vol * 0.5, 'sine');
    this.playNoise(duration, vol * 0.5);
  }

  public toggleMute(): void { this.isMuted = !this.isMuted; }
  public isSoundMuted(): boolean { return this.isMuted; }
  public setSFXVolume(v: number): void { this.volume = Math.max(0, Math.min(1, v)); }
  public destroy(): void { if (this.ctx) this.ctx.close(); }
}
