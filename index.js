// 主窗口：主界面 + 选区界面（由后端 eval 或事件切换，不跳转页面）
import { listen } from '@tauri-apps/api/event';
import { invoke } from '@tauri-apps/api/core';

const mainView = document.getElementById('main-view');
const captureView = document.getElementById('capture-view');
const overlay = document.getElementById('overlay');
const box = document.getElementById('box');
const selectionInfo = document.getElementById('selection-info');
const hint = document.getElementById('hint');
const errorEl = document.getElementById('error-msg');

function logToFile(msg) {
  invoke('log_from_frontend', { message: msg }).catch(() => {});
}

function showError(msg) {
  if (!errorEl) return;
  errorEl.textContent = String(msg);
  errorEl.style.display = 'block';
  setTimeout(() => { errorEl.style.display = 'none'; }, 8000);
}

let startX = 0, startY = 0, currentX = 0, currentY = 0;
let keyHandler = null;
let mousedownHandler = null;

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
  // 锚点与尺寸显示在选区内（左上角内嵌 8px，避免被菜单栏挡住）
  if (selectionInfo) {
    if (w > 0 && h > 0) {
      selectionInfo.style.left = (x + 8) + 'px';
      selectionInfo.style.top = (y + 8) + 'px';
      selectionInfo.textContent = `锚点 (${Math.round(startX)}, ${Math.round(startY)})  ·  尺寸 ${w} × ${h}`;
      selectionInfo.classList.add('visible');
    } else {
      selectionInfo.classList.remove('visible');
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
    const payload = { region: { x, y, width: w, height: h } };
    // 先隐藏蒙版和选区框，避免被截入图；延迟一帧再截屏，确保合成器已更新
    if (overlay) overlay.style.display = 'none';
    if (box) box.style.display = 'none';
    if (hint) hint.style.visibility = 'hidden';
    const doCapture = () => {
      logToFile('invoking capture_region');
      invoke('capture_region', payload).catch((err) => {
        const msg = err?.message ?? err?.toString?.() ?? String(err);
        logToFile('capture_region error: ' + msg);
        showError('Capture failed: ' + msg);
      });
    };
    requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(doCapture, 50)));
  } else {
    logToFile('invoking close_capture_window');
    invoke('close_capture_window').catch((err) => {
      showError('Close failed: ' + (err?.message || err));
    });
  }
}

function enterCaptureMode() {
  mainView.style.display = 'none';
  captureView.classList.add('active');
  document.body.style.background = 'transparent';
  // 每次进入选区时恢复蒙版/框/提示，避免上次截屏时隐藏后残留
  if (overlay) overlay.style.display = '';
  if (box) box.style.display = '';
  if (hint) hint.style.visibility = '';
  if (selectionInfo) { selectionInfo.classList.remove('visible'); selectionInfo.textContent = ''; }
  // 等窗口完成 resize 后再启用选区，否则后续截图时 clientX/clientY 仍按旧窗口尺寸，导致选区错位
  setTimeout(initCapture, 150);
}

function exitCaptureMode() {
  cleanupCapture();
  mainView.style.display = '';
  document.body.style.background = '#fff';
}

function initCapture() {
  mousedownHandler = (e) => {
    if (e.button !== 0) return;
    startX = currentX = e.clientX;
    startY = currentY = e.clientY;
    updateBox();
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp, { once: true });
    keyHandler = (ev) => {
      if (ev.key === 'Escape') finish(true);
      if (ev.key === 'Enter') finish(false);
    };
    document.addEventListener('keydown', keyHandler);
  };
  document.addEventListener('mousedown', mousedownHandler);
  logToFile('capture mode active');
}

function cleanupCapture() {
  if (mousedownHandler) {
    document.removeEventListener('mousedown', mousedownHandler);
    mousedownHandler = null;
  }
  document.removeEventListener('mousemove', onMove);
  document.removeEventListener('mouseup', onUp);
  if (keyHandler) {
    document.removeEventListener('keydown', keyHandler);
    keyHandler = null;
  }
  captureView.classList.remove('active');
  mainView.style.display = '';
  document.body.style.background = '#fff';
}

// 等待 Tauri 注入完成后再挂载（dev 下脚本可能晚于 module 执行）
function waitForTauri(maxMs = 3000) {
  return new Promise((resolve, reject) => {
    if (window.__TAURI_INTERNALS__) {
      resolve();
      return;
    }
    const deadline = Date.now() + maxMs;
    const tick = () => {
      if (window.__TAURI_INTERNALS__) {
        resolve();
        return;
      }
      if (Date.now() >= deadline) {
        reject(new Error('Tauri API not ready'));
        return;
      }
      setTimeout(tick, 50);
    };
    setTimeout(tick, 0);
  });
}

window.__enterCaptureMode = enterCaptureMode;
window.__exitCaptureMode = exitCaptureMode;

async function doFullScreen() {
  try {
    await invoke('capture_fullscreen');
    logToFile('capture_fullscreen ok');
  } catch (e) {
    const msg = e?.message ?? e?.toString?.() ?? String(e);
    logToFile('capture_fullscreen error: ' + msg);
    showError('Full screen capture failed: ' + msg);
  }
}

waitForTauri()
  .then(() => {
    listen('enter-capture-mode', enterCaptureMode);
    listen('exit-capture-mode', exitCaptureMode);
    const btn = document.getElementById('btn-fullscreen');
    if (btn) btn.addEventListener('click', doFullScreen);
  })
  .catch(() => {
    if (errorEl) {
      errorEl.textContent = 'Tauri API not ready. Restart the app.';
      errorEl.style.display = 'block';
    }
  });
