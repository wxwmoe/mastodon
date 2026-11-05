import { fromJS } from 'immutable';
import { Provider } from 'react-redux';

import { configureStore } from '@reduxjs/toolkit';

import { openModal } from 'mastodon/actions/modal';
import { render, fireEvent, screen } from '@/testing/rendering';

import MediaAttachments from '../media_attachments';
import MediaGallery from '../media_gallery';

vi.mock('mastodon/features/video', () => ({ formatTime: String }));

const attachments = (count, type = 'image') => fromJS(Array.from({ length: count }, (_, index) => ({
  id: `${index}`,
  type,
  url: `https://example.com/media/${index}`,
  remote_url: `https://remote.example/media/${index}`,
  preview_url: type === 'image' ? `https://example.com/preview/${index}` : null,
  description: '',
  meta: { original: { width: 640, height: 480, duration: 3 } },
})));

describe('attachment galleries', () => {
  it.each([4, 5, 16])('previews four of %i attachments and opens the original list and index', count => {
    const media = attachments(count);
    const onOpenMedia = vi.fn();
    const { container } = render(<MediaGallery media={media} height={110} lang='en' onOpenMedia={onOpenMedia} />);

    expect(container.querySelectorAll('.media-gallery__item').length).toBe(4);
    expect(container.firstChild.classList.contains('media-gallery--layout-4')).toBe(true);
    fireEvent.click(container.querySelectorAll('.media-gallery__item-thumbnail')[3]);
    expect(onOpenMedia).toHaveBeenLastCalledWith(media, 3, 'en');

    if (count > 4) {
      const more = screen.getByRole('button', { name: `Show ${count - 4} more attachments` });
      expect(more.textContent).toContain(`+${count - 4}`);
      fireEvent.click(more);
      expect(onOpenMedia).toHaveBeenLastCalledWith(media, 4, 'en');
    } else {
      expect(screen.queryByRole('button', { name: /more attachments/ })).toBeNull();
    }
  });

  it.each(['image', 'audio', 'unknown'])('requires revealing sensitive %s attachments before opening them', type => {
    const media = attachments(16, type);
    const onOpenMedia = vi.fn();
    const { container } = render(<MediaGallery media={media} height={110} sensitive onOpenMedia={onOpenMedia} />);

    expect(container.querySelector('.media-gallery__item-thumbnail')).toBeNull();
    expect(screen.queryByRole('button', { name: /more attachments/ })).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: /Click to show/ }));
    expect(onOpenMedia).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Show 12 more attachments' }));
    expect(onOpenMedia).toHaveBeenCalledWith(media, 4, undefined);
    fireEvent.click(container.querySelectorAll('.media-gallery__item-thumbnail')[2]);
    expect(onOpenMedia).toHaveBeenLastCalledWith(media, 2, undefined);
  });

  it.each(['audio', 'video'])('opens every historical attachment when its first item is %s', type => {
    const media = attachments(16).setIn([0, 'type'], type);
    const status = fromJS({ language: 'en', sensitive: false }).set('media_attachments', media);
    const store = configureStore({ reducer: (state = {}) => state });
    const dispatch = vi.spyOn(store, 'dispatch');

    render(<Provider store={store}><MediaAttachments status={status} /></Provider>);

    return screen.findByRole('button', { name: 'Show 12 more attachments' }).then(button => {
      fireEvent.click(button);
      expect(dispatch).toHaveBeenCalledWith(openModal({
        modalType: 'MEDIA',
        modalProps: { media, index: 4, lang: 'en' },
      }));
    });
  });
});
