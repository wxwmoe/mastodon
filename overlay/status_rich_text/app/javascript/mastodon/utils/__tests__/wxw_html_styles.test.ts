import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { htmlStringToComponents } from '../html';

afterEach(() => vi.restoreAllMocks());

describe('rich text styles', () => {
  it.each(['div', 'h1', 'span'])(
    'preserves styles on %s when template CSS declarations are empty',
    (tag) => {
      const nativeStyle = Object.getOwnPropertyDescriptor(
        HTMLElement.prototype,
        'style',
      );
      const emptyStyle = document.createElement('span').style;
      vi.spyOn(HTMLElement.prototype, 'style', 'get').mockImplementation(
        function (this: HTMLElement) {
          return this.ownerDocument === document
            ? (nativeStyle?.get?.call(this) as CSSStyleDeclaration)
            : emptyStyle;
        },
      );

      const html = renderToStaticMarkup(
        htmlStringToComponents(
          `<${tag} style="background-color: red; color: yellow; font-size: 28px; font-weight: 700; line-height: 1.4; text-align: center; padding: 16px 12px; border-radius: 4px; position: fixed; opacity: 0; margin: 32px !important;" onclick="alert(1)">one<br>two</${tag}>`,
        ),
      );
      const result = document.createElement('div');
      result.innerHTML = html;
      const element = result.firstElementChild as HTMLElement;

      expect(element.tagName.toLowerCase()).toBe(tag);
      expect(element.style.backgroundColor).toBe('red');
      expect(element.style.color).toBe('yellow');
      expect(element.style.fontSize).toBe('28px');
      expect(element.style.fontWeight).toBe('700');
      expect(element.style.lineHeight).toBe('1.4');
      expect(element.style.textAlign).toBe('center');
      expect(element.style.paddingTop).toBe('16px');
      expect(element.style.paddingLeft).toBe('12px');
      expect(
        element.style.borderTopLeftRadius || element.style.borderRadius,
      ).toBe('4px');
      expect(element.style.position).toBe('');
      expect(element.style.opacity).toBe('');
      expect(element.style.margin).toBe('');
      expect(element.hasAttribute('onclick')).toBe(false);
      expect(element.innerHTML).toBe('one<br>two');
    },
  );
});
