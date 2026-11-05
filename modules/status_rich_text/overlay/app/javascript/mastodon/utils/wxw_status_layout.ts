export function observeStatusContent(
  node: HTMLElement,
  maxHeight: number,
  onResize: (collapsed: boolean) => void,
) {
  const text = node.querySelector<HTMLElement>(
    ':scope > .status__content__text',
  );
  const measure = () => {
    onResize(
      node.scrollHeight > maxHeight ||
        (text !== null && text.scrollWidth > text.clientWidth),
    );
  };

  measure();
  const observer = new ResizeObserver(measure);
  observer.observe(text ?? node);
  return () => {
    observer.disconnect();
  };
}
