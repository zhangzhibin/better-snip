// 选区：拖拽画矩形，松开发送 rect 给 Rust
function logToFile(msg) {
  if (window.__TAURI__?.core?.invoke) {
    window.__TAURI__.core.invoke('log_from_frontend', { message: msg }).catch(() => {});
  }
}
logToFile('capture page loaded');

const overlay = document.getElementById('overlay');
const box = document.getElementById('box');
const hint = document.getElementById('hint');
const errorEl = document.getElementById('error-msg');

function showError(msg) {
  errorEl.textContent = String(msg);
  errorEl.style.display = 'block';
  setTimeout(() => { errorEl.style.display = 'none'; }, 8000);
}

let startX = 0, startY = 0;
let currentX = 0, currentY = 0;

function updateBox() {
  const x = Math.min(startX, currentX);
  const y = Math.min(startY, currentY);
  const w = Math.abs(currentX - startX);
  const h = Math.abs(currentY - startY);
  box.style.left = x + 'px';
  box.style.top = y + 'px';
  box.style.width = w + 'px';
  box.style.height = h + 'px';
  box.style.display = w > 0 && h > 0 ? 'block' : 'none';
  overlay.classList.toggle('has-selection', w > 0 && h > 0);
}

let keyHandler = null;

function finish(cancel) {
  document.removeEventListener('mousemove', onMove);
  document.removeEventListener('mouseup', onUp);
  if (keyHandler) {
    document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
  }
  const x = Math.min(startX, currentX);
  const y = Math.min(startY, currentY);
  const w = Math.abs(currentX - startX);
  const h = Math.abs(currentY - startY);
  logToFile('finish(cancel=' + cancel + ') w=' + w + ' h=' + h);
  if (!cancel && w >= 2 && h >= 2) {
    const payload = { x, y, width: w, height: h };
    if (!window.__TAURI__?.core?.invoke) {
      logToFile('no __TAURI__.core.invoke');
      showError('Tauri API not loaded. Run from app.');
      return;
    }
    logToFile('invoking capture_region');
    window.__TAURI__.core.invoke('capture_region', payload).catch((err) => {
      const errMsg = (err?.message || String(err));
      logToFile('capture_region failed: ' + errMsg);
      showError('Capture failed: ' + errMsg);
    });
  } else {
    if (window.__TAURI__?.core?.invoke) {
      logToFile('invoking close_capture_window');
      window.__TAURI__.core.invoke('close_capture_window').catch((err) => {
        logToFile('close_capture_window failed: ' + (err?.message || err));
        showError('Close failed: ' + (err?.message || err));
      });
    }
  }
}

function onMove(e) {
  currentX = e.clientX;
  currentY = e.clientY;
  updateBox();
}

function onUp() {
  finish(false);
}

document.addEventListener('mousedown', (e) => {
  if (e.button !== 0) return;
  startX = currentX = e.clientX;
  startY = currentY = e.clientY;
  updateBox();
  document.addEventListener('mousemove', onMove);
  document.addEventListener('mouseup', onUp, { once: true });
  keyHandler = (e) => {
    if (e.key === 'Escape') finish(true);
    if (e.key === 'Enter') finish(false);
  };
  document.addEventListener('keydown', keyHandler);
});
