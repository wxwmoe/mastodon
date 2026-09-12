import { wxwFormatFromSource } from './wxw_format';

describe('wxwFormatFromSource', () => {
  test.each([
    ['text/plain', 'plain'],
    ['text/markdown', 'markdown'],
    ['text/html', 'html'],
  ] as const)(
    'restores %s without rewriting the original text',
    (contentType, format) => {
      for (const text of [
        '',
        '  **literal** &amp; @alice #tag :blob_cat:  \n\nline\t',
        '<p><strong>HTML</strong><br> &lt;b&gt;literal&lt;/b&gt;</p>',
        '```html\n<b> @alice #tag\n```\n',
      ]) {
        expect(wxwFormatFromSource(text, contentType)).toEqual({ text, format });
      }
    },
  );
});
