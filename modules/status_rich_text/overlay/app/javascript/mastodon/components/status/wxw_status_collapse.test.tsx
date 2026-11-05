import { configureStore } from '@reduxjs/toolkit';
import { Provider } from 'react-redux';

import { afterEach, expect, it, vi } from 'vitest';

import { StatusQuoteManager } from '@/mastodon/components/status_quoted';
import { reducerWithInitialState } from '@/mastodon/reducers';
import { defaultMiddleware } from '@/mastodon/store/store';
import {
  accountFactoryImmutable,
  statusFactoryAPI,
  statusFactoryImmutable,
  statusQuotedFactoryAPI,
} from '@/testing/factories';
import { act, cleanup, render, within } from '@/testing/rendering';

import { StatusContent } from './content';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

it.each(['timeline', 'content'])(
  'keeps each %s copy of a status independently collapsible',
  (view) => {
    const original = statusFactoryAPI({
      text: 'The shared post.',
      spoiler_text: '',
    });
    const store = configureStore({
      reducer: reducerWithInitialState({
        accounts: { '1': accountFactoryImmutable() },
        statuses: {
          '1': statusFactoryImmutable(original),
          '2': statusFactoryImmutable({
            id: '2',
            quote: {
              state: 'accepted',
              quoted_status: statusQuotedFactoryAPI({ id: original.id }),
            },
          }),
          '3': statusFactoryImmutable({ id: '3', reblog: original }),
        },
      }),
      middleware: (getDefaultMiddleware) =>
        getDefaultMiddleware(defaultMiddleware),
    });
    const callbacks = new Set<() => void>();
    vi.stubGlobal(
      'ResizeObserver',
      class {
        constructor(private callback: () => void) {}
        observe() {
          callbacks.add(this.callback);
        }
        disconnect() {
          callbacks.delete(this.callback);
        }
      },
    );
    vi.spyOn(Element.prototype, 'scrollHeight', 'get').mockImplementation(
      function (this: Element) {
        return Number(
          this.closest<HTMLElement>('[data-height]')?.dataset.height ?? 0,
        );
      },
    );

    const copy = <StatusContent statusId='1' collapsible onClick={vi.fn()} />;
    const { getByTestId } = render(
      <Provider store={store}>
        <div data-testid='quote' data-height='329'>
          {view === 'timeline' ? <StatusQuoteManager id='2' /> : copy}
        </div>
        <div data-testid='boost' data-height='527'>
          {view === 'timeline' ? <StatusQuoteManager id='3' /> : copy}
        </div>
      </Provider>,
    );
    const quote = within(getByTestId('quote'));
    const boost = within(getByTestId('boost'));
    const readMore = { name: 'Read more' };
    expect(quote.queryByText('The shared post.')).not.toBeNull();
    expect(quote.queryByRole('button', readMore)).toBeNull();
    expect(boost.queryByRole('button', readMore)).not.toBeNull();
    act(() => {
      getByTestId('boost').dataset.height = '329';
      for (const callback of [...callbacks]) callback();
    });
    expect(boost.queryByRole('button', readMore)).toBeNull();
  },
);
