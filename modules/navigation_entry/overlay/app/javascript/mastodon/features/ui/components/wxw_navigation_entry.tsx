import type { IntlShape } from 'react-intl';

import PawIcon from '@/material-icons/400-24px/paw.svg?react';
import { Icon } from 'mastodon/components/icon';

export const navigationEntry = (intl: IntlShape) => ({
  title: intl.formatMessage({ id: 'column.firehose', defaultMessage: 'Live feeds' }),
  to: '/public/local',
  icon: <Icon id='' icon={PawIcon} />,
});
