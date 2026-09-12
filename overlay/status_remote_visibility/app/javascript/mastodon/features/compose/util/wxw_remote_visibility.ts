import { createAction } from '@reduxjs/toolkit';

import type { ApiQuotePolicy } from '@/mastodon/api_types/quotes';
import type { StatusVisibility } from '@/mastodon/api_types/statuses';
import type { RootState } from '@/mastodon/store';
import { uuid } from '@/mastodon/uuid';
import { wxwNormalizeRemoteVisibility } from '@/wxw_remote_visibility/visibility';

export { wxwNormalizeRemoteVisibility };

type ComposeState = RootState['compose'];

export const changeComposeRemoteVisibility =
  createAction<StatusVisibility | null>('compose/wxw_remote_visibility_change');

export const wxwQuoteVisibility = (
  visibility: StatusVisibility,
  remoteVisibility: unknown,
): StatusVisibility => {
  if (visibility === 'direct' || remoteVisibility === 'direct') return 'direct';
  if (visibility === 'private' || remoteVisibility === 'private')
    return 'private';
  return visibility;
};

export const wxwQuoteRestricted = (
  visibility: StatusVisibility,
  remoteVisibility: unknown,
) =>
  ['private', 'direct'].includes(
    wxwQuoteVisibility(visibility, remoteVisibility),
  );

export const wxwNormalizeComposeRemoteVisibility = (state: ComposeState) =>
  state.set(
    'wxw_remote_visibility',
    wxwNormalizeRemoteVisibility(
      state.get('privacy') as StatusVisibility,
      state.get('wxw_remote_visibility') as StatusVisibility | null,
    ),
  );

export const wxwSetComposeRemoteVisibility = (
  state: ComposeState,
  remoteVisibility: StatusVisibility | null,
) => {
  const normalizedState = wxwNormalizeComposeRemoteVisibility(state);
  const nextState = wxwNormalizeComposeRemoteVisibility(
    normalizedState.set('wxw_remote_visibility', remoteVisibility),
  );

  return nextState.get('wxw_remote_visibility') ===
    normalizedState.get('wxw_remote_visibility')
    ? nextState
    : nextState.set('idempotencyKey', uuid());
};

export const wxwComposeVisibilityParams = (state: ComposeState) => {
  const visibility = state.get('privacy') as StatusVisibility;
  const remoteVisibility = wxwNormalizeRemoteVisibility(
    visibility,
    state.get('wxw_remote_visibility') as StatusVisibility | null,
  );

  return {
    wxw_remote_visibility: remoteVisibility,
    quote_approval_policy: wxwQuoteRestricted(visibility, remoteVisibility)
      ? 'nobody'
      : (state.get('quote_policy') as ApiQuotePolicy),
  };
};
