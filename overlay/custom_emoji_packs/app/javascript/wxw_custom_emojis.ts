import ready from './mastodon/ready';

const itemSelector = '[data-wxw-sortable-item]';
const handleSelector = '[data-wxw-sortable-handle]';

const setupSortable = (container: HTMLElement) => {
  let active:
    | {
        handle: HTMLButtonElement;
        item: HTMLElement;
        pointerId: number;
      }
    | undefined;

  const finish = (event: PointerEvent) => {
    if (!active || active.pointerId !== event.pointerId) return;

    active.item.classList.remove('wxw-sortable__item--dragging');
    if (active.handle.hasPointerCapture(event.pointerId)) {
      active.handle.releasePointerCapture(event.pointerId);
    }
    active = undefined;
  };

  container.addEventListener('pointerdown', (event) => {
    if (
      !event.isPrimary ||
      (event.pointerType === 'mouse' && event.button !== 0)
    )
      return;
    if (!(event.target instanceof Element)) return;

    const handle = event.target.closest<HTMLButtonElement>(handleSelector);
    const item = handle?.closest<HTMLElement>(itemSelector);
    if (!handle || !item || item.parentElement !== container) return;

    event.preventDefault();
    active = { handle, item, pointerId: event.pointerId };
    item.classList.add('wxw-sortable__item--dragging');
    handle.setPointerCapture(event.pointerId);
  });

  container.addEventListener('pointermove', (event) => {
    if (!active || active.pointerId !== event.pointerId) return;

    event.preventDefault();
    const target = document
      .elementFromPoint(event.clientX, event.clientY)
      ?.closest<HTMLElement>(itemSelector);
    if (!target || target === active.item || target.parentElement !== container)
      return;

    const bounds = target.getBoundingClientRect();
    if (event.clientY < bounds.top + bounds.height / 2) {
      target.before(active.item);
    } else {
      target.after(active.item);
    }

    const edge = 48;
    if (event.clientY < edge) window.scrollBy(0, -16);
    if (event.clientY > window.innerHeight - edge) window.scrollBy(0, 16);
  });

  container.addEventListener('pointerup', finish);
  container.addEventListener('pointercancel', finish);

  container
    .querySelectorAll<HTMLButtonElement>(handleSelector)
    .forEach((handle) => {
      handle.addEventListener('keydown', (event) => {
        if (!['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key))
          return;

        const item = handle.closest<HTMLElement>(itemSelector);
        if (!item || item.parentElement !== container) return;

        event.preventDefault();
        const items = Array.from(
          container.querySelectorAll<HTMLElement>(itemSelector),
        );
        const index = items.indexOf(item);
        if (event.key === 'ArrowUp' && index > 0)
          items[index - 1]?.before(item);
        if (event.key === 'ArrowDown' && index < items.length - 1)
          items[index + 1]?.after(item);
        if (event.key === 'Home') container.prepend(item);
        if (event.key === 'End') container.append(item);
        handle.focus();
      });
    });
};

void ready(() => {
  document
    .querySelectorAll<HTMLElement>('[data-wxw-sortable]')
    .forEach(setupSortable);
});
