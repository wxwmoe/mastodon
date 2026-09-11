import { useEffect, useRef } from 'react';

import { List as ImmutableList } from 'immutable';

import type { MediaAttachment } from '@/mastodon/models/status';
import AttachmentList from 'mastodon/components/attachment_list';
import { Audio } from 'mastodon/features/audio';

const stopPropagation = (event: React.SyntheticEvent) => {
  event.stopPropagation();
};

export function useMediaPlaybackCleanup(
  index: number,
  media: ImmutableList<MediaAttachment>,
) {
  const modalRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const players =
      modalRef.current?.querySelectorAll<HTMLMediaElement>('audio, video');

    return () => {
      players?.forEach((player) => {
        player.pause();
      });
    };
  }, [index, media]);

  return modalRef;
}

export function renderExtraMediaSlide(
  item: MediaAttachment,
  distance: number,
  playback: {
    lang?: string;
    startTime: number;
    startPlaying: boolean;
    startVolume?: number;
  },
) {
  const key = item.get('id') as string;
  const url = item.get('url') as string;
  const type = item.get('type') as string;

  if (distance !== 0 && (type !== 'image' || Math.abs(distance) > 1)) {
    return <div key={key} />;
  }

  if (!url || !['image', 'video', 'gifv', 'audio'].includes(type)) {
    return (
      <div key={key} role='presentation' onClick={stopPropagation}>
        <AttachmentList media={ImmutableList.of(item)} />
      </div>
    );
  }

  if (type !== 'audio') {
    return undefined;
  }

  const description = item.getIn(
    ['translation', 'description'],
    item.get('description'),
  ) as string;

  return (
    <div key={key} role='presentation' onClick={stopPropagation}>
      <div className='audio-modal__container' onPointerDown={stopPropagation}>
        <Audio
          src={url}
          alt={description}
          poster={item.get('preview_url') as string | undefined}
          duration={item.getIn(['meta', 'original', 'duration'], 0) as number}
          backgroundColor={
            item.getIn(['meta', 'colors', 'background']) as string
          }
          foregroundColor={
            item.getIn(['meta', 'colors', 'foreground']) as string
          }
          accentColor={item.getIn(['meta', 'colors', 'accent']) as string}
          {...playback}
        />
      </div>
    </div>
  );
}
