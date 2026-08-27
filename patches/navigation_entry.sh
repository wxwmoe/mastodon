#!/bin/bash
set -e

grep -Fqx "import SearchIcon from '@/material-icons/400-24px/search.svg?react';" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "  menu: { id: 'tabs_bar.menu', defaultMessage: 'Menu' }," src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              title={intl.formatMessage(messages.search)}" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              to='/explore'" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              icon={<Icon id='' icon={SearchIcon} />}" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
sed -i -e "s|^import SearchIcon from '@/material-icons/400-24px/search.svg?react';$|import PawIcon from '@/material-icons/400-24px/paw.svg?react';|" -e "s|^  menu: { id: 'tabs_bar.menu', defaultMessage: 'Menu' },$|&\n  firehose: { id: 'column.firehose', defaultMessage: 'Live feeds' },|" -e "s|^              title={intl.formatMessage(messages.search)}$|              title={intl.formatMessage(messages.firehose)}|" -e "s|^              to='/explore'$|              to='/public/local'|" -e "s|^              icon={<Icon id='' icon={SearchIcon} />}$|              icon={<Icon id='' icon={PawIcon} />}|" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "import PawIcon from '@/material-icons/400-24px/paw.svg?react';" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "  firehose: { id: 'column.firehose', defaultMessage: 'Live feeds' }," src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              title={intl.formatMessage(messages.firehose)}" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              to='/public/local'" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
grep -Fqx "              icon={<Icon id='' icon={PawIcon} />}" src/app/javascript/mastodon/features/ui/components/navigation_bar.tsx
