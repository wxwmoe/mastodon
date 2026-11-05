// @ts-check

/**
 * @param {string | undefined} value
 * @returns {(payload: string, host?: string) => string}
 */
export function createMediaHostRewriter(value) {
  const config = value?.trim() ? JSON.parse(value) : {};

  if (!config || typeof config !== 'object' || Array.isArray(config)) {
    throw new TypeError('STREAMING_MEDIA_HOSTS must map request hosts to source replacements');
  }

  /** @type {Map<string, { pattern: RegExp, targets: Map<string, string> }>} */
  const replacements = new Map();

  for (const [host, sources] of Object.entries(config)) {
    if (!host.trim() || !sources || typeof sources !== 'object' || Array.isArray(sources)) {
      throw new TypeError('STREAMING_MEDIA_HOSTS requires a non-empty request host and an object of replacements');
    }

    const targets = new Map();

    for (const [source, target] of Object.entries(sources)) {
      if (!source.trim() || typeof target !== 'string' || !target.trim()) {
        throw new TypeError('STREAMING_MEDIA_HOSTS requires non-empty source and target addresses');
      }

      targets.set(source, target);
    }

    if (targets.size === 0) continue;

    const keys = [...targets.keys()].sort((left, right) => right.length - left.length);
    const pattern = new RegExp(keys.map(source => source.replace(/[.*+?^$(){}|[\]\\]/g, '\\$&')).join('|'), 'g');
    replacements.set(host.toLowerCase(), { pattern, targets });
  }

  return (payload, host) => {
    const rules = replacements.get(host?.replace(/:[0-9]+$/, '').toLowerCase() ?? '');
    return rules ? payload.replace(rules.pattern, source => rules.targets.get(source) ?? source) : payload;
  };
}
