export class UIManager {
  private scoreEl!: HTMLElement;
  private distanceEl!: HTMLElement;
  private weaponEl!: HTMLElement;
  private comboEl!: HTMLElement;
  private hpFill!: HTMLElement;
  private hpText!: HTMLElement;
  private bossContainer!: HTMLElement;
  private bossName!: HTMLElement;
  private bossHpFill!: HTMLElement;
  private startScreen!: HTMLElement;
  private gameOverScreen!: HTMLElement;
  private finalScore!: HTMLElement;
  private finalDistance!: HTMLElement;
  private finalKills!: HTMLElement;
  private loadingEl!: HTMLElement;

  private startCb?: () => void;
  private restartCb?: () => void;
  private speedChangeCb?: (speed: number) => void;
  private spawnRateChangeCb?: (interval: number) => void;

  public initialize(): void {
    this.scoreEl = this.el('score-display');
    this.distanceEl = this.el('distance-display');
    this.weaponEl = this.el('weapon-display');
    this.comboEl = this.el('combo-display');
    this.hpFill = this.el('hp-bar-fill');
    this.hpText = this.el('hp-text');
    this.bossContainer = this.el('boss-hp-container');
    this.bossName = this.el('boss-name');
    this.bossHpFill = this.el('boss-hp-fill');
    this.startScreen = this.el('start-screen');
    this.gameOverScreen = this.el('game-over-screen');
    this.finalScore = this.el('final-score');
    this.finalDistance = this.el('final-distance');
    this.finalKills = this.el('final-kills');
    this.loadingEl = this.el('loading');

    this.loadingEl.classList.add('hidden');

    this.el('start-button').addEventListener('click', () => this.startCb?.());
    this.el('restart-button').addEventListener('click', () => this.restartCb?.());

    // Speed slider
    const speedSlider = this.el('speed-slider') as HTMLInputElement;
    const speedValue = this.el('speed-value');
    speedSlider.addEventListener('input', () => {
      const v = parseFloat(speedSlider.value);
      speedValue.textContent = `${v.toFixed(1)}x`;
      this.speedChangeCb?.(v);
    });

    // Spawn rate slider
    const spawnSlider = this.el('spawn-slider') as HTMLInputElement;
    const spawnValue = this.el('spawn-value');
    spawnSlider.addEventListener('input', () => {
      const v = parseFloat(spawnSlider.value) / 10;
      const label = v < 1.0 ? 'Insane' : v < 1.5 ? 'Very High' : v < 2.0 ? 'High' : v < 2.5 ? 'Normal' : v < 3.0 ? 'Low' : 'Very Low';
      spawnValue.textContent = label;
      this.spawnRateChangeCb?.(v);
    });
  }

  public updateScore(score: number): void { this.scoreEl.textContent = score.toLocaleString(); }
  public updateDistance(d: number): void { this.distanceEl.textContent = `${Math.floor(d)}m`; }

  public updateWeapon(name: string): void { this.weaponEl.textContent = name.toUpperCase(); }

  public updateHP(current: number, max: number): void {
    const pct = Math.max(0, current / max) * 100;
    this.hpFill.style.width = `${pct}%`;

    // Color shift: green → yellow → red
    if (pct > 60) {
      this.hpFill.style.background = 'linear-gradient(90deg, #22C55E, #4ADE80)';
    } else if (pct > 30) {
      this.hpFill.style.background = 'linear-gradient(90deg, #FBBF24, #FCD34D)';
    } else {
      this.hpFill.style.background = 'linear-gradient(90deg, #EF4444, #F87171)';
    }

    this.hpText.textContent = `HP ${current}/${max}`;
  }

  public showCombo(combo: number): void {
    this.comboEl.textContent = `x${combo} COMBO`;
    this.comboEl.classList.add('visible');
  }
  public hideCombo(): void { this.comboEl.classList.remove('visible'); }

  public showBossHP(name: string, current: number, max: number): void {
    this.bossContainer.style.display = 'block';
    this.bossName.textContent = name;
    this.bossHpFill.style.width = `${Math.max(0, (current / max) * 100)}%`;
  }
  public updateBossHP(current: number, max: number): void {
    this.bossHpFill.style.width = `${Math.max(0, (current / max) * 100)}%`;
  }
  public hideBossHP(): void { this.bossContainer.style.display = 'none'; }

  public showStartScreen(): void { this.startScreen.classList.remove('hidden'); }
  public hideStartScreen(): void { this.startScreen.classList.add('hidden'); }

  public showGameOver(score: number, distance: number, kills: number): void {
    this.finalScore.textContent = score.toLocaleString();
    this.finalDistance.textContent = Math.floor(distance).toString();
    this.finalKills.textContent = kills.toString();
    this.gameOverScreen.classList.remove('hidden');
  }
  public hideGameOver(): void { this.gameOverScreen.classList.add('hidden'); }

  public onStartGame(cb: () => void): void { this.startCb = cb; }
  public onRestartGame(cb: () => void): void { this.restartCb = cb; }
  public onSpeedChange(cb: (speed: number) => void): void { this.speedChangeCb = cb; }
  public onSpawnRateChange(cb: (interval: number) => void): void { this.spawnRateChangeCb = cb; }

  private el(id: string): HTMLElement {
    const e = document.getElementById(id);
    if (!e) throw new Error(`UI element #${id} not found`);
    return e;
  }
}
