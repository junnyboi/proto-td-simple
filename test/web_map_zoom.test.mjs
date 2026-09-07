import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import test from 'node:test';

const source = readFileSync(new URL('../scripts/view/web_map_zoom.gd', import.meta.url), 'utf8');
const script = source.split('const INSTALL_SCRIPT := """')[1].split('"""')[0];
function setup() {
  const handlers = new Map();
  const calls = [];
  const canvas = {
    clientHeight: 720,
    getBoundingClientRect: () => ({ left: 100, top: 50, width: 1280, height: 720 }),
    addEventListener(type, handler, options) {
      assert.equal(options.passive, false);
      assert.equal(options.capture, true);
      handlers.set(type, handler);
    },
    removeEventListener(type) { handlers.delete(type); },
  };
  const window = { addEventListener() {}, removeEventListener() {} };
  runInNewContext(script, { window, document: { getElementById: () => canvas } });
  const bridge = window.__tdInstallMapZoom((...args) => calls.push(args));
  function send(type, values) {
    const event = { clientX: 740, clientY: 410, deltaY: 0, deltaMode: 0,
      prevented: false, stopped: false,
      preventDefault() { this.prevented = true; },
      stopImmediatePropagation() { this.stopped = true; }, ...values };
    handlers.get(type)(event);
    return event;
  }
  return { calls, bridge, handlers, send };
}

test('wheel and Ctrl-wheel pinch change world zoom, cancel page zoom, preserve canvas coordinates', () => {
  const { calls, send } = setup();
  const event = send('wheel', { deltaY: -100 });
  assert.ok(event.prevented && event.stopped);
  assert.deepEqual(calls[0].slice(0, 2), [0.5, 0.5]);
  assert.ok(calls[0][2] > 1);
  send('wheel', { deltaY: 100 });
  assert.ok(Math.abs(calls[0][2] * calls[1][2] - 1) < 1e-10);
  send('wheel', { deltaY: -5, ctrlKey: true });
  assert.ok(calls[2][2] > 1 && calls[2][2] < calls[0][2]);
  const shifted = send('wheel', { deltaY: 100, shiftKey: true });
  assert.equal(shifted.prevented, false);
  assert.equal(calls.length, 3);
});

test('Safari magnify is incremental, deduplicates wheel, and removes listeners on scene exit', () => {
  const { calls, send, bridge, handlers } = setup();
  assert.ok(send('gesturestart', { scale: 1 }).prevented);
  send('gesturechange', { scale: 1.5 });
  send('gesturechange', { scale: 1.2 });
  assert.equal(calls[0][2], 1.5);
  assert.ok(Math.abs(calls[1][2] - 0.8) < 1e-10);
  send('wheel', { deltaY: -10, ctrlKey: true });
  assert.equal(calls.length, 2);
  send('gestureend', {});
  send('wheel', { deltaY: -10 });
  assert.equal(calls.length, 3);
  bridge.dispose();
  assert.equal(handlers.size, 0);
});
