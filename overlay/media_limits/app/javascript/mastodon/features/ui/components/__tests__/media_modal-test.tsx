import { List, fromJS } from 'immutable';

import type { MediaAttachment } from '@/mastodon/models/status';
import { fireEvent, render, screen } from '@/testing/rendering';

import { MediaModal } from '../media_modal';

const { animate } = vi.hoisted(() => ({ animate: vi.fn() }));

vi.mock('@react-spring/web', () => ({
  animated: { div: 'div' },
  useSpring: () => [{}, { start: animate }],
}));
vi.mock('@use-gesture/react', () => ({ useDrag: () => () => ({}) }));
vi.mock('mastodon/features/picture_in_picture/components/footer', () => ({
  Footer: () => null,
}));
vi.mock('../zoomable_image', () => ({
  ZoomableImage: ({ src }: { src: string }) => (
    <div className='zoomable-image'>
      <img src={src} alt='' />
    </div>
  ),
}));
vi.mock('mastodon/features/video', () => ({
  Video: ({
    src,
    startTime,
    startPlaying,
    startVolume,
  }: {
    src: string;
    startTime: number;
    startPlaying: boolean;
    startVolume: number;
  }) => (
    <div>
      <video
        src={src}
        data-start-time={startTime}
        data-start-playing={startPlaying}
        data-start-volume={startVolume}
      >
        <track kind='captions' />
      </video>
    </div>
  ),
}));
vi.mock('mastodon/features/audio', () => ({
  Audio: ({ src, startVolume }: { src: string; startVolume?: number }) => (
    <audio src={src} data-start-volume={startVolume}>
      <track kind='captions' />
    </audio>
  ),
}));

it('keeps all 16 mixed-media page indexes and stops each player when leaving its page', () => {
  const pause = vi
    .spyOn(HTMLMediaElement.prototype, 'pause')
    .mockImplementation(() => undefined);
  const onClose = vi.fn();
  const media = List(
    Array.from(
      { length: 16 },
      (_, i) =>
        fromJS({
          id: String(i),
          type:
            (
              { 3: 'video', 4: 'audio', 5: 'gifv', 15: 'unknown' } as Record<
                number,
                string
              >
            )[i] ?? 'image',
          url: i === 15 ? null : `https://local.test/${i}.media`,
          remote_url: `https://remote.test/${i}.media`,
        }) as unknown as MediaAttachment,
    ),
  );

  const { container, unmount } = render(
    <MediaModal
      media={media}
      index={3}
      currentTime={42}
      volume={0.25}
      autoPlay
      onClose={onClose}
      onChangeBackgroundColor={vi.fn()}
    />,
  );
  const pages = container.querySelector('.media-modal__closer');
  const video = container.querySelector('video');
  expect(pages?.children.length).toBe(16);
  expect(video?.getAttribute('src')).toBe('https://local.test/3.media');
  expect(video?.dataset).toMatchObject({
    startTime: '42',
    startPlaying: 'true',
    startVolume: '0.25',
  });
  expect(container.querySelectorAll('audio, video').length).toBe(1);

  fireEvent.click(screen.getByRole('button', { name: 'Next' }));
  const audio = container.querySelector('audio');
  expect(audio?.getAttribute('src')).toBe('https://local.test/4.media');
  expect(audio?.dataset.startVolume).toBe('0.25');
  expect(pause.mock.contexts).toContain(video);
  expect(pages?.children.length).toBe(16);
  expect(container.querySelectorAll('audio, video').length).toBe(1);

  fireEvent.click(screen.getByRole('button', { name: 'Next' }));
  const gifv = container.querySelector('video');
  expect(gifv?.getAttribute('src')).toBe('https://local.test/5.media');
  expect(pause.mock.contexts).toContain(audio);

  fireEvent.click(screen.getByRole('button', { name: '16' }));
  expect(animate).toHaveBeenLastCalledWith({ x: 'calc(-1500% + 0px)' });
  expect(pause.mock.contexts).toContain(gifv);
  expect(container.querySelectorAll('audio, video').length).toBe(0);
  expect(pages?.children.length).toBe(16);
  fireEvent.click(screen.getByRole('link', { name: '15.media' }));
  expect(screen.getByRole('link').getAttribute('href')).toBe(
    'https://remote.test/15.media',
  );
  expect(onClose).not.toHaveBeenCalled();

  fireEvent.keyDown(window, { key: 'ArrowRight' });
  expect(
    container.querySelector('.media-modal__page-dot.active')?.textContent,
  ).toBe('1');
  fireEvent.click(screen.getByRole('button', { name: '9' }));
  expect(pages?.querySelectorAll(':scope > .zoomable-image').length).toBe(3);

  fireEvent.click(screen.getByRole('button', { name: '4' }));
  const lastPlayer = container.querySelector('video');
  unmount();
  expect(pause.mock.contexts).toContain(lastPlayer);
  pause.mockRestore();
});

it.each([undefined, 0])(
  'preserves an audio volume of %s without defaulting to full volume',
  (volume) => {
    const pause = vi
      .spyOn(HTMLMediaElement.prototype, 'pause')
      .mockImplementation(() => undefined);
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
        volume={volume}
        onClose={vi.fn()}
        onChangeBackgroundColor={vi.fn()}
      />,
    );

    expect(container.querySelector('audio')?.dataset.startVolume).toBe(
      volume?.toString(),
    );
    unmount();
    pause.mockRestore();
  },
);
