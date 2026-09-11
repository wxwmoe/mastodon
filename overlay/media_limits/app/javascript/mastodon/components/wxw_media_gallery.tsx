import type { MouseEvent, MouseEventHandler, ReactEventHandler } from 'react';
import { useCallback } from 'react';

import { FormattedMessage } from 'react-intl';

import type { MediaAttachment } from '@/mastodon/models/status';
import HeadphonesIcon from '@/material-icons/400-24px/headphones-fill.svg?react';
import LinkIcon from '@/material-icons/400-24px/link.svg?react';
import { Icon } from 'mastodon/components/icon';

export const WxwMediaThumbnail = ({
  attachment,
  lang,
  description,
  onClick,
  onLoad,
  onError,
}: {
  attachment: MediaAttachment;
  lang?: string;
  description?: string;
  onClick: MouseEventHandler<HTMLAnchorElement>;
  onLoad: ReactEventHandler<HTMLImageElement>;
  onError: ReactEventHandler<HTMLImageElement>;
}) => {
  const audio = attachment.get('type') === 'audio';
  const preview = attachment.get('preview_url') as string | undefined;

  return (
    <a
      className='media-gallery__item-thumbnail'
      href={(attachment.get('remote_url') || attachment.get('url')) as string}
      onClick={onClick}
      lang={lang}
      target='_blank'
      rel='noopener'
    >
      {audio && preview && (
        <img src={preview} alt='' onLoad={onLoad} onError={onError} />
      )}
      <span className='media-gallery__item__overlay'>
        <Icon
          id={audio ? 'music' : 'link'}
          icon={audio ? HeadphonesIcon : LinkIcon}
        />
      </span>
      <span className='sr-only'>
        {description?.length ? (
          description
        ) : audio ? (
          <FormattedMessage id='media_gallery.audio' defaultMessage='Audio' />
        ) : (
          <FormattedMessage
            id='status.media.open'
            defaultMessage='Click to open'
          />
        )}
      </span>
    </a>
  );
};

export const WxwMoreMediaButton = ({
  count,
  onOpen,
}: {
  count: number;
  onOpen: (index: number) => void;
}) => {
  const handleClick = useCallback(
    (event: MouseEvent<HTMLButtonElement>) => {
      event.stopPropagation();
      onOpen(4);
    },
    [onOpen],
  );

  return count > 4 ? (
    <button
      type='button'
      className='media-gallery__actions__pill'
      onClick={handleClick}
    >
      <span aria-hidden='true'>+{count - 4}</span>
      <span className='sr-only'>
        <FormattedMessage
          id='media_gallery.show_more'
          defaultMessage='Show {count} more attachments'
          values={{ count: count - 4 }}
        />
      </span>
    </button>
  ) : null;
};
