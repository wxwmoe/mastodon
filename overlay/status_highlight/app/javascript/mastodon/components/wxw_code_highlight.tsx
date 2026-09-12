import type { ComponentProps, CSSProperties } from 'react';
import { createElement, Fragment, useEffect, useState } from 'react';

import type { ThemedToken } from 'shiki/core';

import { useVisibility } from '@/mastodon/hooks/useVisibility';
import type { OnElementHandler } from '@/mastodon/utils/html';
import '@/styles/mastodon/wxw_code_highlight.scss';

interface CodeHighlightProps extends ComponentProps<'code'> {
  text: string;
  language: string;
}

const CodeHighlight = ({
  text,
  language,
  className,
  ...props
}: CodeHighlightProps) => {
  const { observedRef, isIntersecting } = useVisibility();
  const [result, setResult] = useState<{
    text: string;
    language: string;
    tokens: ThemedToken[][];
  }>();
  const tokens =
    result?.text === text && result.language === language
      ? result.tokens
      : undefined;

  useEffect(() => {
    if (!isIntersecting || tokens) return;

    let cancelled = false;
    void import('@/mastodon/utils/wxw_code_highlight')
      .then(async ({ highlightCode }) => {
        const highlighted = await highlightCode(text, language);
        if (!cancelled && highlighted) {
          setResult({ text, language, tokens: highlighted });
        }
      })
      .catch(() => {
        // Keep the original code readable if a grammar or engine cannot load.
      });

    return () => {
      cancelled = true;
    };
  }, [isIntersecting, language, text, tokens]);

  const lineEndings = text.match(/\r\n|\r|\n/g) ?? [];

  return (
    <code
      {...props}
      ref={observedRef}
      className={tokens ? `${className ?? ''} wxw-code-highlight` : className}
    >
      {tokens
        ? tokens.map((line, lineIndex) => (
            <Fragment key={lineIndex}>
              {line.map((token, tokenIndex) => (
                <span key={tokenIndex} style={token.htmlStyle as CSSProperties}>
                  {token.content}
                </span>
              ))}
              {lineEndings[lineIndex]}
            </Fragment>
          ))
        : text}
    </code>
  );
};

export function withCodeHighlight(
  onElement?: OnElementHandler,
): OnElementHandler {
  const handleCodeElement: OnElementHandler = (...args) => {
    const existing = onElement?.(...args);
    if (existing !== undefined) return existing;

    const [element, props] = args;
    if (
      element.tagName !== 'CODE' ||
      element.parentElement?.tagName !== 'PRE' ||
      element.childElementCount > 0
    )
      return undefined;

    const text = element.textContent;
    const language = Array.from(element.classList)
      .find((name) => /^language-[a-z0-9][a-z0-9_+.#-]{0,63}$/i.test(name))
      ?.slice(9)
      .toLowerCase();

    // Bound main-thread tokenization; use a worker if larger blocks need highlighting.
    if (
      !language ||
      text.length > 20_000 ||
      text.split(/\r\n|\r|\n/).length > 500
    ) {
      return createElement('code', props, text);
    }

    return createElement(CodeHighlight, { ...props, text, language });
  };
  return handleCodeElement;
}
