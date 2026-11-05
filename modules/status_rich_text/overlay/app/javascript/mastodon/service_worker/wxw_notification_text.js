import { unescape } from 'lodash';

export const htmlToPlainText = html => {
  let text = '';
  let pendingBoundary = false;

  // Push payloads contain HTML sanitized by the API.
  for (const [index, part] of html.replace(/<\/p><p>/g, '\n\n').split(/(<(?:[^>"']|"[^"]*"|'[^']*')*>)/g).entries()) {
    if (index % 2 === 1) {
      if (/^<br(?=[\s/>])/i.test(part)) {
        text += '\n';
        pendingBoundary = false;
      } else if (/^<\/?(?:p|h[1-6]|ul|ol|li|blockquote|pre|div|hr|details|summary|dl|dt|dd|header|footer|hgroup)(?=[\s/>])/i.test(part)) {
        pendingBoundary = text.length > 0;
      }
    } else if (part) {
      if (pendingBoundary && !text.endsWith('\n') && !part.startsWith('\n')) text += '\n';
      text += part;
      pendingBoundary = false;
    }
  }

  return unescape(text);
};
