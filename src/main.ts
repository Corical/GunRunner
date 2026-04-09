import { GameManager } from './core/GameManager';

async function main() {
  try {
    const canvas = document.getElementById('renderCanvas') as HTMLCanvasElement;
    if (!canvas) throw new Error('Canvas not found');

    const game = GameManager.getInstance();
    await game.initialize(canvas);

    console.log('GunRunner initialized');
  } catch (error) {
    console.error('Failed to initialize:', error);
    const loading = document.getElementById('loading');
    if (loading) {
      loading.textContent = 'Failed to load. Please refresh.';
      loading.style.color = 'red';
    }
  }
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', main);
} else {
  main();
}
