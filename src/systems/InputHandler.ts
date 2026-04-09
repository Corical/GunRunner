import { LaneDirection } from '@/core/Config';

export class InputHandler {
  private inputQueue: LaneDirection[] = [];
  private touchStartX: number = 0;
  private keyStates: Map<string, boolean> = new Map();
  private lastKeyPressTime: Map<string, number> = new Map();

  public initialize(): void {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('touchstart', this.onTouchStart, { passive: false });
    window.addEventListener('touchmove', this.onTouchMove, { passive: false });
    window.addEventListener('touchend', this.onTouchEnd);
  }

  public getInputDirection(): LaneDirection {
    return this.inputQueue.length > 0 ? this.inputQueue.shift()! : LaneDirection.NONE;
  }

  private onKeyDown = (e: KeyboardEvent): void => {
    const now = performance.now();
    const debounce = 100;

    if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
      const last = this.lastKeyPressTime.get('left') || 0;
      if (!this.keyStates.get('left') || now - last > debounce) {
        this.inputQueue.push(LaneDirection.LEFT);
        this.lastKeyPressTime.set('left', now);
      }
      this.keyStates.set('left', true);
      e.preventDefault();
    } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
      const last = this.lastKeyPressTime.get('right') || 0;
      if (!this.keyStates.get('right') || now - last > debounce) {
        this.inputQueue.push(LaneDirection.RIGHT);
        this.lastKeyPressTime.set('right', now);
      }
      this.keyStates.set('right', true);
      e.preventDefault();
    }
  };

  private onKeyUp = (e: KeyboardEvent): void => {
    if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
      this.keyStates.set('left', false);
    } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
      this.keyStates.set('right', false);
    }
  };

  private onTouchStart = (e: TouchEvent): void => {
    if (e.touches.length > 0) this.touchStartX = e.touches[0].clientX;
    e.preventDefault();
  };

  private onTouchMove = (e: TouchEvent): void => {
    if (e.touches.length > 0 && this.touchStartX > 0) {
      const dx = e.touches[0].clientX - this.touchStartX;
      if (Math.abs(dx) > 50) {
        this.inputQueue.push(dx > 0 ? LaneDirection.RIGHT : LaneDirection.LEFT);
        this.touchStartX = 0;
      }
    }
    e.preventDefault();
  };

  private onTouchEnd = (_e: TouchEvent): void => {
    this.touchStartX = 0;
  };

  public dispose(): void {
    window.removeEventListener('keydown', this.onKeyDown);
    window.removeEventListener('keyup', this.onKeyUp);
    window.removeEventListener('touchstart', this.onTouchStart);
    window.removeEventListener('touchmove', this.onTouchMove);
    window.removeEventListener('touchend', this.onTouchEnd);
  }
}
