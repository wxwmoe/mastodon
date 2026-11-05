import { WORD } from '../../utils/hashtags';

export const tokenRegex = (tokens: string[]) =>
  new RegExp(`[${tokens.join('')}${WORD}+-]+$`, 'iu');
