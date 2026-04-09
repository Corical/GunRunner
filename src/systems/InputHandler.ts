export class InputHandler {
  // Continuous movement: -1 (left held), 0 (nothing), 1 (right held)
  private moveDirection: number = 0;
  private speedChangeCb?: (delta: number) => void;

  // Touch tracking
  private touchActive: boolean = false;
  private touchCurrentX: number = 0;
  private touchCenterX: number = 0;

  public initialize(): void {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('touchstart', this.onTouchStart, { passive: false });
    window.addEventListener('touchmove', this.onTouchMove, { passive: false });
    window.addEventListener('touchend', this.onTouchEnd);
  }

  /** Returns continuous movement: -1 (left), 0 (idle), 1 (right) */
  public getMoveDirection(): number {
    if (this.touchActive) {
      // Touch: map finger position to movement
      const dx = this.touchCurrentX - this.touchCenterX;
      const threshold = 20;
      if (dx < -threshold) return -1;
      if (dx > threshold) return 1;
      return 0;
    }
    return this.moveDirection;
  }

  private onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
      this.moveDirection = -1;
      e.preventDefault();
    } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
      this.moveDirection = 1;
      e.preventDefault();
    } else if (e.key === 'ArrowUp') {
      this.speedChangeCb?.(0.1);
      e.preventDefault();
    } else if (e.key === 'ArrowDown') {
      this.speedChangeCb?.(-0.1);
      e.preventDefault();
    }
  };

  private onKeyUp = (e: KeyboardEvent): void => {
    if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
      if (this.moveDirection === -1) this.moveDirection = 0;
    } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
      if (this.moveDirection === 1) this.moveDirection = 0;
    }
  };

  private onTouchStart = (e: TouchEvent): void => {
    if (e.touches.length > 0) {
      this.touchActive = true;
      this.touchCenterX = e.touches[0].clientX;
      this.touchCurrentX = e.touches[0].clientX;
    }
    e.preventDefault();
  };

  private onTouchMove = (e: TouchEvent): void => {
    if (e.touches.length > 0 && this.touchActive) {
      this.touchCurrentX = e.touches[0].clientX;
    }
    e.preventDefault();
  };

  private onTouchEnd = (_e: TouchEvent): void => {
    this.touchActive = false;
    this.moveDirection = 0;
  };

  public onSpeedChange(cb: (delta: number) => void): void {
    this.speedChangeCb = cb;
  }

  public dispose(): void {
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    window.removeEventListener('touchstart', this.onTouchStart);
    window.removeEventListener('touchmove', this.onTouchMove);
    window.removeEventListener('touchend', this.onTouchEnd);
  }
}
