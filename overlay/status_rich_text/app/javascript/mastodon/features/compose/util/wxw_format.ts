const formats = {
  'text/plain': 'plain',
  'text/markdown': 'markdown',
  'text/html': 'html',
} as const;

export type WxwFormat = (typeof formats)[keyof typeof formats];

export function wxwFormatFromSource(
  text: string,
  contentType: keyof typeof formats,
): { text: string; format: WxwFormat } {
  return { text, format: formats[contentType] };
}
