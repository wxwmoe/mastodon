import { afterEach, expect, it, vi } from 'vitest';

import { observeStatusContent } from '../wxw_status_layout';

afterEach(() => vi.unstubAllGlobals());

it('remeasures growing and shrinking content and disconnects on cleanup', () => {
  let resize: () => void = vi.fn();
  const observe = vi.fn();
  const disconnect = vi.fn();
  vi.stubGlobal(
    'ResizeObserver',
    class {
      constructor(callback: () => void) {
        resize = callback;
      }
      observe = observe;
      disconnect = disconnect;
    },
  );
  const node = document.createElement('div');
  node.innerHTML = '<div class="status__content__text">banner</div>';
  const text = node.firstElementChild;
  let height = 100;
  let width = 300;
  Object.defineProperty(node, 'scrollHeight', { get: () => height });
  Object.defineProperty(text, 'scrollWidth', { get: () => width });
  Object.defineProperty(text, 'clientWidth', { value: 300 });
  const changed = vi.fn();

  const cleanup = observeStatusContent(node, 440, changed);
  expect(observe).toHaveBeenCalledWith(text);
  expect(changed).toHaveBeenLastCalledWith(false);
  height = 1200;
  resize();
  expect(changed).toHaveBeenLastCalledWith(true);
  height = 200;
  resize();
  expect(changed).toHaveBeenLastCalledWith(false);
  width = 600;
  resize();
  expect(changed).toHaveBeenLastCalledWith(true);
  cleanup();
  expect(disconnect).toHaveBeenCalledOnce();
});
