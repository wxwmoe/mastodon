const VIEWPORT_GUTTER = 8;
const MAX_PREVIEW_SIZE = 200;

let previewSource: HTMLImageElement | null = null;
let previewImage: HTMLImageElement | null = null;
let suppressClickSource: HTMLImageElement | null = null;

function clearPreview() {
  previewImage?.remove();
  previewImage = null;
  previewSource = null;
}

function showPreview(image: HTMLImageElement, source: HTMLImageElement) {
  if (
    previewImage !== image ||
    previewSource !== source ||
    !source.isConnected
  ) {
    return;
  }

  const viewportWidth = document.documentElement.clientWidth;
  const viewportHeight = document.documentElement.clientHeight;
  const availableWidth = viewportWidth - VIEWPORT_GUTTER * 2;
  const availableHeight = viewportHeight - VIEWPORT_GUTTER * 2;

  if (
    image.naturalWidth === 0 ||
    image.naturalHeight === 0 ||
    availableWidth <= 0 ||
    availableHeight <= 0
  ) {
    clearPreview();
    return;
  }

  const scale = Math.min(
    1,
    MAX_PREVIEW_SIZE / image.naturalWidth,
    MAX_PREVIEW_SIZE / image.naturalHeight,
    availableWidth / image.naturalWidth,
    availableHeight / image.naturalHeight,
  );
  const width = image.naturalWidth * scale;
  const height = image.naturalHeight * scale;
  const sourceRect = source.getBoundingClientRect();
  const left = Math.min(
    Math.max(
      sourceRect.left + sourceRect.width / 2 - width / 2,
      VIEWPORT_GUTTER,
    ),
    viewportWidth - VIEWPORT_GUTTER - width,
  );
  const top = Math.min(
    Math.max(
      sourceRect.top + sourceRect.height / 2 - height / 2,
      VIEWPORT_GUTTER,
    ),
    viewportHeight - VIEWPORT_GUTTER - height,
  );

  image.style.left = `${left}px`;
  image.style.top = `${top}px`;
  image.style.width = `${width}px`;
  image.style.height = `${height}px`;
  image.hidden = false;
}

function getPreviewSource(target: EventTarget | null) {
  if (
    !(target instanceof HTMLImageElement) ||
    !target.classList.contains('custom-emoji') ||
    target.closest('.emoji-mart') !== null
  ) {
    return null;
  }

  return target;
}

function createPreview(target: HTMLImageElement) {
  const source = [target.dataset.original, target.currentSrc, target.src].find(
    Boolean,
  );
  if (!source) {
    return;
  }

  clearPreview();

  const image = new Image();
  image.className = 'custom-emoji-preview';
  image.alt = '';
  image.hidden = true;
  image.draggable = false;
  image.decoding = 'async';
  image.setAttribute('aria-hidden', 'true');

  previewSource = target;
  previewImage = image;

  image.addEventListener(
    'load',
    () => {
      showPreview(image, target);
    },
    { once: true },
  );
  image.addEventListener(
    'error',
    () => {
      if (previewImage === image) {
        clearPreview();
      }
    },
    { once: true },
  );

  document.body.append(image);
  image.src = source;

  if (image.complete) {
    showPreview(image, target);
  }
}

export function setupCustomEmojiPreview() {
  document.addEventListener('pointerover', (event) => {
    const target = getPreviewSource(event.target);

    if (
      event.pointerType === 'touch' ||
      target === null ||
      target === previewSource
    ) {
      return;
    }

    createPreview(target);
  });

  document.addEventListener(
    'pointerdown',
    (event) => {
      if (event.pointerType !== 'touch') {
        return;
      }

      suppressClickSource = null;
      const target = getPreviewSource(event.target);
      if (target === null) {
        clearPreview();
        return;
      }

      if (target === previewSource) {
        clearPreview();
        return;
      }

      event.preventDefault();
      event.stopPropagation();
      createPreview(target);
      suppressClickSource = target;
    },
    true,
  );

  document.addEventListener(
    'click',
    (event) => {
      const source = suppressClickSource;
      suppressClickSource = null;
      if (source === null || !event.composedPath().includes(source)) {
        return;
      }

      event.preventDefault();
      event.stopPropagation();
    },
    true,
  );

  document.addEventListener('pointerout', (event) => {
    if (event.pointerType !== 'touch' && event.target === previewSource) {
      clearPreview();
    }
  });
  document.addEventListener('pointercancel', () => {
    clearPreview();
    suppressClickSource = null;
  });
  document.addEventListener('scroll', clearPreview, {
    capture: true,
    passive: true,
  });
  window.addEventListener('resize', clearPreview, { passive: true });
}
