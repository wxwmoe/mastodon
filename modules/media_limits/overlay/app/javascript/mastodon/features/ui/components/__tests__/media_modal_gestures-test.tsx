import { List, fromJS } from 'immutable';

import type { MediaAttachment } from '@/mastodon/models/status';
import { fireEvent, render, screen } from '@/testing/rendering';

import { MediaModal } from '../media_modal';

vi.hoisted(() => {
  vi.stubGlobal(
    'PointerEvent',
    class extends MouseEvent {
      pointerId: number;
      pointerType: string;

      constructor(type: string, options: PointerEventInit = {}) {
        super(type, options);
        this.pointerId = options.pointerId ?? 1;
        this.pointerType = options.pointerType ?? 'mouse';
      }
    },
  );
});

vi.mock('mastodon/features/picture_in_picture/components/footer', () => ({
  Footer: () => null,
}));
vi.mock('../zoomable_image', () => ({
  ZoomableImage: () => <div className='zoomable-image' />,
}));

it.each(['mouse', 'touch'])(
  'keeps %s gestures on audio controls out of lightbox navigation',
  (pointerType) => {
    const pause = vi
      .spyOn(HTMLMediaElement.prototype, 'pause')
      .mockImplementation(() => undefined);
    const onClose = vi.fn();
    const media = List(
      [
        { id: 'audio', type: 'audio', url: 'https://local.test/audio.ogg' },
        { id: 'image', type: 'image', url: 'https://local.test/image.png' },
      ].map((item) => fromJS(item) as unknown as MediaAttachment),
    );
    const { container, unmount } = render(
      <MediaModal
        media={media}
        index={0}
        onClose={onClose}
        onChangeBackgroundColor={vi.fn()}
      />,
    );
    const audio = container.querySelector('audio');
    if (!audio) throw new Error('Missing audio player');
    Object.defineProperty(audio, 'duration', { value: 100 });
    const gesture = { pointerId: 1, pointerType, clientY: 100, buttons: 1 };
    const drag = (target: Element) => {
      fireEvent.pointerDown(target, { ...gesture, clientX: 100 });
      if (pointerType === 'mouse')
        fireEvent.mouseDown(target, { clientX: 100, buttons: 1 });
      fireEvent.pointerMove(window, { ...gesture, clientX: 600 });
      if (pointerType === 'mouse')
        fireEvent.mouseMove(document, { clientX: 600, buttons: 1 });
      fireEvent.pointerUp(window, { ...gesture, clientX: 600, buttons: 0 });
      if (pointerType === 'mouse') fireEvent.mouseUp(document);
    };

    for (const selector of ['.video-player__seek', '.video-player__volume']) {
      const slider = container.querySelector(selector);
      if (!slider) throw new Error('Missing audio slider');
      Object.defineProperties(slider, {
        offsetWidth: { value: 1000 },
        offsetHeight: { value: 20 },
      });
      drag(slider);
      expect(container.querySelector('audio')).toBe(audio);
      expect(
        container.querySelector('.media-modal__page-dot.active')?.textContent,
      ).toBe('1');
    }
    if (pointerType === 'mouse') {
      expect(audio.currentTime).toBe(60);
      expect(audio.volume).toBe(0.6);
    }
    fireEvent.click(screen.getByRole('button', { name: 'Skip forward' }));
    expect(audio.currentTime).toBe(pointerType === 'mouse' ? 65 : 5);
    expect(onClose).not.toHaveBeenCalled();

    const slide = container.querySelector('.media-modal__closer > div');
    if (!slide) throw new Error('Missing media slide');
    drag(slide);
    expect(
      container.querySelector('.media-modal__page-dot.active')?.textContent,
    ).toBe('2');
    expect(container.querySelector('audio')).toBeNull();
    unmount();
    pause.mockRestore();
  },
);
