import type { StatusVisibility } from '@/mastodon/api_types/statuses';

const visibilityOrder = ['public', 'unlisted', 'private', 'direct'];

export const wxwRemoteVisibilityAllowed = (
  visibility: string,
  remoteVisibility: string,
): remoteVisibility is StatusVisibility => {
  const localIndex = visibilityOrder.indexOf(visibility);
  return (
    localIndex !== -1 && visibilityOrder.indexOf(remoteVisibility) >= localIndex
  );
};

export const wxwNormalizeRemoteVisibility = (
  visibility: string,
  remoteVisibility: string | null | undefined,
): StatusVisibility | null =>
  remoteVisibility &&
  remoteVisibility !== visibility &&
  wxwRemoteVisibilityAllowed(visibility, remoteVisibility)
    ? remoteVisibility
    : null;
