import { isValidElement } from 'react';

import { act, cleanup, render, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { htmlStringToComponents } from '@/mastodon/utils/html';
import * as highlighter from '@/mastodon/utils/wxw_code_highlight';

import { withCodeHighlight } from './wxw_code_highlight';

vi.mock('@/mastodon/hooks/useVisibility', () => ({
  useVisibility: () => ({ observedRef: vi.fn(), isIntersecting: true }),
}));

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const convert = (html: string) =>
  htmlStringToComponents(html, { onElement: withCodeHighlight() });

const codeElement = (text: string) => {
  const pre = document.createElement('pre');
  const code = pre.appendChild(document.createElement('code'));
  code.className = 'language-js';
  code.textContent = text;
  return withCodeHighlight()(
    code,
    { key: 'code', title: 'source', dir: 'ltr' },
    [],
    {},
  );
};

describe('code highlighting', () => {
  it.each(['JS', 'c++', 'c#'])(
    'loads the %s language alias',
    async (language) => {
      const { container } = render(
        <>
          {convert(
            `<pre><code class="language-${language}">const answer = 42;</code></pre>`,
          )}
        </>,
      );

      await waitFor(() => {
        expect(
          container.querySelector('code.wxw-code-highlight'),
        ).not.toBeNull();
      });
      expect(container.querySelector('code')?.textContent).toBe(
        'const answer = 42;',
      );
      const style = container.querySelector('code span')?.getAttribute('style');
      for (const theme of ['light', 'dark', 'light-high', 'dark-high']) {
        expect(style).toContain(`--shiki-${theme}:`);
      }
    },
  );

  it('preserves escaped code, emoji, indentation, empty lines and final newline', async () => {
    const source = '<script>alert("😀")</script>\n  const x = 1;\n\n';
    const escaped = document.createElement('span');
    escaped.textContent = source;
    const { container } = render(
      <>
        {htmlStringToComponents(
          `<p>😀</p><pre><code class="language-html">${escaped.innerHTML}</code></pre>`,
          {
            onElement: withCodeHighlight(),
            onText: (text) => text.replaceAll('😀', 'emoji replacement'),
          },
        )}
      </>,
    );

    await waitFor(() => {
      expect(container.querySelector('code.wxw-code-highlight')).not.toBeNull();
    });
    expect(container.querySelector('p')?.textContent).toBe('emoji replacement');
    expect(container.querySelector('code')?.textContent).toBe(source);
    expect(container.querySelector('script')).toBeNull();
  });

  it('leaves unknown, unlabelled, inline and nested code readable', async () => {
    const highlight = vi.spyOn(highlighter, 'highlightCode');
    const { container } = render(
      <>
        {convert(
          '<pre><code class="language-unknown">unknown</code></pre><pre><code>plain</code></pre><code class="language-js">inline</code><pre><code class="language-js">a<br>b</code></pre><pre><code class="language-js"><span>nested</span></code></pre>',
        )}
      </>,
    );

    await act(async () => {
      await vi.dynamicImportSettled();
    });
    expect(highlight).toHaveBeenCalledExactlyOnceWith('unknown', 'unknown');
    expect(container.textContent).toBe('unknownplaininlineabnested');
    expect(container.querySelector('.wxw-code-highlight')).toBeNull();
    expect(container.querySelector('code br')).not.toBeNull();
    expect(container.querySelector('code span')?.textContent).toBe('nested');
  });

  it('preserves existing element overrides, including null', () => {
    const { container } = render(
      <>
        {htmlStringToComponents(
          '<pre><code class="language-js">hidden</code></pre>',
          {
            onElement: withCodeHighlight((element) =>
              element.tagName === 'CODE' ? null : undefined,
            ),
          },
        )}
      </>,
    );
    expect(container.querySelector('code')).toBeNull();
    expect(container.textContent).toBe('');
  });

  it.each([
    { limit: 'characters', source: 'x'.repeat(20_001) },
    { limit: 'lines', source: 'x\n'.repeat(500) },
  ])('keeps code exceeding the $limit limit plain', ({ source }) => {
    const highlight = vi.spyOn(highlighter, 'highlightCode');
    const { container } = render(<>{codeElement(source)}</>);
    expect(container.textContent).toBe(source);
    expect(container.querySelector('.wxw-code-highlight')).toBeNull();
    expect(highlight).not.toHaveBeenCalled();
  });

  it('passes the original key and attributes through and preserves CRLF', async () => {
    const source = 'const a = 1;\r\n\r\n';
    const element = codeElement(source);
    expect(isValidElement(element) && element.key).toBe('code');
    const { container } = render(element);
    await waitFor(() => {
      expect(container.querySelector('.wxw-code-highlight')).not.toBeNull();
    });
    const code = container.querySelector('code');
    expect(code?.title).toBe('source');
    expect(code?.dir).toBe('ltr');
    expect(code?.textContent).toBe(source);
  });

  it('ignores a pending result after editing or unmounting', async () => {
    const tokens = [[{ content: 'old result', offset: 0 }]];
    let finish: ((value: typeof tokens) => void) | undefined;
    const pending = new Promise<typeof tokens>((resolve) => {
      finish = resolve;
    });
    let finishUnmounted: ((value: typeof tokens) => void) | undefined;
    const unmountedPending = new Promise<typeof tokens>((resolve) => {
      finishUnmounted = resolve;
    });
    const highlight = vi
      .spyOn(highlighter, 'highlightCode')
      .mockReturnValueOnce(pending)
      .mockResolvedValueOnce([[{ content: 'new source', offset: 0 }]])
      .mockReturnValueOnce(unmountedPending);
    const { container, rerender, unmount } = render(
      <>{codeElement('old source')}</>,
    );
    await waitFor(() => {
      expect(highlight).toHaveBeenCalledTimes(1);
    });

    rerender(<>{codeElement('new source')}</>);
    expect(container.textContent).toBe('new source');
    await waitFor(() => {
      expect(container.querySelector('.wxw-code-highlight')).not.toBeNull();
    });
    await act(async () => {
      finish?.(tokens);
      await pending;
    });
    expect(container.textContent).toBe('new source');

    rerender(<>{codeElement('unmounted source')}</>);
    await waitFor(() => {
      expect(highlight).toHaveBeenCalledTimes(3);
    });
    unmount();
    await act(async () => {
      finishUnmounted?.(tokens);
      await unmountedPending;
    });
    expect(container.textContent).toBe('');
  });
});
