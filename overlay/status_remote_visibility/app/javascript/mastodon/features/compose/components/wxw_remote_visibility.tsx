import { useCallback, useId, useMemo, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import classNames from 'classnames';

import { isStatusVisibility } from '@/mastodon/api_types/statuses';
import type { StatusVisibility } from '@/mastodon/api_types/statuses';
import { Dropdown } from '@/mastodon/components/dropdown';
import type { SelectItem } from '@/mastodon/components/dropdown_selector';
import { useAppSelector } from '@/mastodon/store';
import AlternateEmailIcon from '@/material-icons/400-24px/alternate_email.svg?react';
import LockIcon from '@/material-icons/400-24px/lock.svg?react';
import PublicIcon from '@/material-icons/400-24px/public.svg?react';
import QuietTimeIcon from '@/material-icons/400-24px/quiet_time.svg?react';
import { wxwRemoteVisibilityAllowed } from '@/wxw_remote_visibility/visibility';

import {
  wxwNormalizeRemoteVisibility,
  wxwQuoteRestricted,
  wxwQuoteVisibility,
} from '../util/wxw_remote_visibility';

import { messages as privacyMessages } from './privacy_dropdown';

const messages = defineMessages({
  remoteVisibility: {
    id: 'privacy.wxw_remote_visibility',
    defaultMessage:
      '{visibility}, other servers: {remoteVisibility, select, public {Public} unlisted {Quiet public} private {Followers} direct {Private mention} other {{remoteVisibility}}}',
  },
});

export const useWxwRemoteVisibility = (
  visibility: StatusVisibility,
  statusId?: string,
) => {
  const initialOverride =
    useAppSelector(
      (state) =>
        (statusId
          ? state.statuses.getIn([statusId, 'wxw_remote_visibility'])
          : state.compose.get('wxw_remote_visibility')) as
          | StatusVisibility
          | null
          | undefined,
    ) ?? null;
  const [override, setOverride] = useState(
    wxwNormalizeRemoteVisibility(visibility, initialOverride),
  );
  const onChange = useCallback(
    (value: string) => {
      if (isStatusVisibility(value)) {
        setOverride(wxwNormalizeRemoteVisibility(visibility, value));
      }
    },
    [visibility],
  );
  const follow = useCallback((value: StatusVisibility) => {
    setOverride((current) => wxwNormalizeRemoteVisibility(value, current));
  }, []);

  return {
    visibility,
    override,
    value: override ?? visibility,
    quoteVisibility: wxwQuoteVisibility(visibility, override),
    onChange,
    follow,
  };
};

export const WxwRemoteVisibilityField = ({
  selection,
  disabled,
}: {
  selection: ReturnType<typeof useWxwRemoteVisibility>;
  disabled: boolean;
}) => {
  const intl = useIntl();
  const uniqueId = useId();
  const labelId = `${uniqueId}-remote-visibility-label`;
  const descriptionId = `${uniqueId}-remote-visibility-description`;
  const items = useMemo<SelectItem<StatusVisibility>[]>(
    () => ([
      {
        value: 'public',
        text: intl.formatMessage(privacyMessages.public_short),
        meta: intl.formatMessage(privacyMessages.public_long),
        icon: 'globe',
        iconComponent: PublicIcon,
      },
      {
        value: 'unlisted',
        text: intl.formatMessage(privacyMessages.unlisted_short),
        meta: intl.formatMessage(privacyMessages.unlisted_long),
        icon: 'unlock',
        iconComponent: QuietTimeIcon,
      },
      {
        value: 'private',
        text: intl.formatMessage(privacyMessages.private_short),
        meta: intl.formatMessage(privacyMessages.private_long),
        icon: 'lock',
        iconComponent: LockIcon,
      },
      {
        value: 'direct',
        text: intl.formatMessage(privacyMessages.direct_short),
        meta: intl.formatMessage(privacyMessages.direct_long),
        icon: 'at',
        iconComponent: AlternateEmailIcon,
      },
    ] satisfies SelectItem<StatusVisibility>[]).filter(({ value }) =>
      wxwRemoteVisibilityAllowed(selection.visibility, value),
    ),
    [intl, selection.visibility],
  );

  return (
    <div className={classNames('visibility-dropdown', { disabled })}>
      {/* eslint-disable-next-line jsx-a11y/label-has-associated-control */}
      <label className='visibility-dropdown__label' id={labelId}>
        <FormattedMessage
          id='visibility_modal.wxw_remote_visibility_label'
          defaultMessage='Other server visibility'
        />
      </label>
      <Dropdown
        items={items}
        current={selection.value}
        onChange={selection.onChange}
        labelId={labelId}
        descriptionId={descriptionId}
        classPrefix='visibility-dropdown'
        disabled={disabled}
      />
      {disabled && (
        <p className='visibility-dropdown__helper' id={descriptionId}>
          <FormattedMessage
            id='visibility_modal.helper.privacy_editing'
            defaultMessage="Visibility can't be changed after a post is published."
          />
        </p>
      )}
    </div>
  );
};

export const useWxwVisibilitySummary = (visibility: StatusVisibility) => {
  const intl = useIntl();
  const remoteVisibility = wxwNormalizeRemoteVisibility(
    visibility,
    useAppSelector(
      (state) =>
        state.compose.get('wxw_remote_visibility') as StatusVisibility | null,
    ),
  );

  return useMemo(() => {
    const text = intl.formatMessage(privacyMessages[`${visibility}_short`]);
    return {
      text: remoteVisibility
        ? intl.formatMessage(messages.remoteVisibility, {
            visibility: text,
            remoteVisibility,
          })
        : text,
      restricted: wxwQuoteRestricted(visibility, remoteVisibility),
    };
  }, [intl, visibility, remoteVisibility]);
};
