import { createHighlighterCore } from 'shiki/core';
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
import { bundledLanguages } from 'shiki/langs';
import githubDarkHighContrast from 'shiki/themes/github-dark-high-contrast.mjs';
import githubDark from 'shiki/themes/github-dark.mjs';
import githubLightHighContrast from 'shiki/themes/github-light-high-contrast.mjs';
import githubLight from 'shiki/themes/github-light.mjs';

let highlighter: ReturnType<typeof createHighlighterCore> | undefined;

export async function highlightCode(text: string, language: string) {
  if (!Object.hasOwn(bundledLanguages, language)) return undefined;

  const grammar = bundledLanguages[language as keyof typeof bundledLanguages];
  const instance = await (highlighter ??= createHighlighterCore({
    engine: createJavaScriptRegexEngine(),
    langs: [],
    themes: [
      githubLight,
      githubDark,
      githubLightHighContrast,
      githubDarkHighContrast,
    ],
  }));
  await instance.loadLanguage(grammar);

  return instance.codeToTokens(text, {
    lang: language,
    themes: {
      light: 'github-light',
      dark: 'github-dark',
      'light-high': 'github-light-high-contrast',
      'dark-high': 'github-dark-high-contrast',
    },
    defaultColor: false,
    tokenizeMaxLineLength: 2_000,
    tokenizeTimeLimit: 10,
  }).tokens;
}
