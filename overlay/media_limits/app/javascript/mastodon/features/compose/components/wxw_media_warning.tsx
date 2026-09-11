import { FormattedMessage } from 'react-intl';

import { WarningMessage } from './warning';

export const WxwMediaWarning = ({ count }: { count: number }) =>
  count > 4 ? (
    <WarningMessage>
      <FormattedMessage
        id='upload_form.federation_limit'
        defaultMessage='Other servers may only show the first 4 attachments.'
      />
    </WarningMessage>
  ) : null;
