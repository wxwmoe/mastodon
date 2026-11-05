import htmlConfig from '../../config/html-tags.json';

// NB: This function can still return unsafe HTML
export const unescapeHTML = (html: string) => {
  const wrapper = document.createElement('template');
  wrapper.innerHTML = html
    .replace(/<br(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>/gi, '\n')
    .replace(/<\/p><p>/g, '\n\n')
    .replace(
      /<(\/?)(p|h[1-6]|ul|ol|li|blockquote|pre|div|hr|details|summary|dl|dt|dd|header|footer|hgroup)(?=[\s/>])(?:[^>"']|"[^"]*"|'[^']*')*>|<(?:[^>"']|"[^"]*"|'[^']*')*>/gi,
      (_, closing: string | undefined, tag: string | undefined) => {
        const name = tag?.toLowerCase();
        // A pre element would consume its leading newline during HTML parsing.
        return name ? `<${closing}${name === 'pre' ? 'div' : name}>` : '';
      },
    );

  // Only block tags survive stripping; decoded literal tags stay text.
  const boundaries = new WeakSet<Node>();
  for (const element of wrapper.content.querySelectorAll('*')) {
    const before = document.createTextNode('');
    const after = document.createTextNode('');
    boundaries.add(before).add(after);
    element.before(before);
    element.after(after);
  }

  const walker = document.createTreeWalker(
    wrapper.content,
    NodeFilter.SHOW_TEXT,
  );
  let text = '';
  let pendingBoundary = false;
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (boundaries.has(node)) {
      pendingBoundary = text.length > 0;
      continue;
    }
    const content = node.textContent ?? '';
    if (
      pendingBoundary &&
      content &&
      !text.endsWith('\n') &&
      !content.startsWith('\n')
    ) {
      text += '\n';
    }
    text += content;
    if (content) pendingBoundary = false;
  }
  return text;
};

const allowedStyles = new Set(
  htmlConfig.styles.flatMap((property) => {
    // Browsers may expose allowed border shorthands as individual CSSOM properties.
    if (/^border-(color|style|width)$/.test(property)) {
      return [
        property,
        ...['top', 'right', 'bottom', 'left'].map((side) =>
          property.replace('border-', `border-${side}-`),
        ),
      ];
    }
    if (property === 'border-radius') {
      return [
        property,
        ...['top-left', 'top-right', 'bottom-right', 'bottom-left'].map(
          (corner) => `border-${corner}-radius`,
        ),
      ];
    }
    return property;
  }),
);

export function richTextStyle(cssText: string) {
  // Template contents may expose an empty CSS declaration in browsers.
  const style = document.createElement('span').style;
  style.cssText = cssText;

  return Object.fromEntries(
    Array.from(style)
      .filter(
        (property) =>
          allowedStyles.has(property) &&
          !style.getPropertyPriority(property),
      )
      .map((property) => [
        property.replace(/-([a-z])/g, (_, letter: string) =>
          letter.toUpperCase(),
        ),
        style.getPropertyValue(property),
      ]),
  );
}
