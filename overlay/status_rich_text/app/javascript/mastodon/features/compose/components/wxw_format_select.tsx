import { useCallback, useEffect, useId, useRef, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';

import classNames from 'classnames';

import CodeIcon from '@/material-icons/400-24px/code.svg?react';
import DescriptionIcon from '@/material-icons/400-24px/description.svg?react';
import MarkdownIcon from '@/material-icons/400-24px/markdown.svg?react';
import { changeComposeFormat } from 'mastodon/actions/compose';
import { Icon } from 'mastodon/components/icon';
import { Popover } from 'mastodon/components/popover';
import { useAppDispatch, useAppSelector } from 'mastodon/store';

const messages = defineMessages({
  label: { id: 'compose.format', defaultMessage: 'Post format' },
  plain: { id: 'compose.format.plain', defaultMessage: 'Plain text' },
  markdown: { id: 'compose.format.markdown', defaultMessage: 'Markdown' },
  html: { id: 'compose.format.html', defaultMessage: 'HTML' },
});

export const WxwFormatSelect: React.FC = () => {
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [open, setOpen] = useState(false);
  const [target, setTarget] = useState<HTMLButtonElement | null>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const menuId = useId();
  const value = useAppSelector(
    (state) => state.compose.get('format') as string,
  );
  const disabled = useAppSelector(
    (state) => state.compose.get('is_submitting') as boolean,
  );
  if (disabled && open) setOpen(false);

  const items = [
    { value: 'plain', text: intl.formatMessage(messages.plain), icon: DescriptionIcon },
    { value: 'markdown', text: intl.formatMessage(messages.markdown), icon: MarkdownIcon },
    { value: 'html', text: intl.formatMessage(messages.html), icon: CodeIcon },
  ];
  const selectedItem = items.find((item) => item.value === value);
  const handleClose = useCallback(() => {
    setOpen(false);
    target?.focus({ preventScroll: true });
  }, [target]);
  const handleToggle = useCallback(() => {
    setOpen((previous) => !previous);
  }, []);
  const handleChange = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      const format = event.currentTarget.getAttribute('data-value');
      if (format) dispatch(changeComposeFormat(format));
      handleClose();
    },
    [dispatch, handleClose],
  );
  const handleKeyDown = useCallback(
    (event: React.KeyboardEvent<HTMLDivElement>) => {
      const options = Array.from(
        listRef.current?.querySelectorAll<HTMLElement>('[role="option"]') ?? [],
      );
      const index = options.indexOf(event.currentTarget);
      let next: HTMLElement | undefined;

      switch (event.key) {
        case 'ArrowDown':
          next = options[index + 1] ?? options[0];
          break;
        case 'ArrowUp':
          next = options[index - 1] ?? options[options.length - 1];
          break;
        case 'Home':
          next = options[0];
          break;
        case 'End':
          next = options[options.length - 1];
          break;
        case 'Enter':
        case ' ':
          event.preventDefault();
          event.currentTarget.click();
          return;
        case 'Tab':
          handleClose();
          return;
      }

      if (next) {
        event.preventDefault();
        next.focus();
      }
    },
    [handleClose],
  );

  useEffect(() => {
    if (open) {
      listRef.current
        ?.querySelector<HTMLElement>('[aria-selected="true"]')
        ?.focus({ preventScroll: true });
    }
  }, [open]);

  return (
    <>
      <button
        type='button'
        ref={setTarget}
        title={intl.formatMessage(messages.label)}
        aria-haspopup='listbox'
        aria-expanded={open}
        aria-controls={menuId}
        disabled={disabled}
        className={classNames('dropdown-button', { active: open })}
        onClick={handleToggle}
      >
        <Icon id={value} icon={selectedItem?.icon ?? DescriptionIcon} />
        <span className='dropdown-button__label'>
          {value === 'markdown' ? 'MD' : selectedItem?.text}
        </span>
      </button>

      <Popover
        isOpen={open}
        onClose={handleClose}
        offset={5}
        reference={target}
      >
        {({ props, placement }) => (
          <div {...props}>
            <div
              className={`dropdown-animation language-dropdown__dropdown ${placement}`}
            >
              <div
                id={menuId}
                ref={listRef}
                role='listbox'
                aria-label={intl.formatMessage(messages.label)}
                className='language-dropdown__dropdown__results emoji-mart-scroll'
                style={{ paddingTop: 10 }}
              >
                {items.map((item) => (
                  <div
                    key={item.value}
                    role='option'
                    tabIndex={0}
                    data-value={item.value}
                    aria-selected={item.value === value}
                    className={classNames(
                      'language-dropdown__dropdown__results__item',
                      { active: item.value === value },
                    )}
                    onClick={handleChange}
                    onKeyDown={handleKeyDown}
                  >
                    <span className='language-dropdown__dropdown__results__item__native-name'>
                      {item.text}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </Popover>
    </>
  );
};
