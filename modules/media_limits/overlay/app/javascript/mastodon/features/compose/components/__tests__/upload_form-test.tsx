import { List, Map as ImmutableMap } from 'immutable';

import { render, screen } from '@/testing/rendering';

import { UploadForm } from '../upload_form';

const { select, dispatch } = vi.hoisted(() => ({
  select: vi.fn(),
  dispatch: vi.fn(),
}));

vi.mock('mastodon/store', () => ({
  useAppSelector: select,
  useAppDispatch: () => dispatch,
}));
vi.mock('mastodon/actions/compose', () => ({ changeMediaOrder: vi.fn() }));
vi.mock('../upload', () => ({
  Upload: ({ id }: { id: string }) => <div data-testid='attachment'>{id}</div>,
}));
vi.mock('../upload_progress', () => ({ UploadProgress: () => null }));
vi.mock('../warning', () => ({
  WarningMessage: ({ children }: React.PropsWithChildren) => (
    <div className='compose-form__warning'>{children}</div>
  ),
}));

it('shows the federation warning above four attachments and removes it when reduced to four', () => {
  const state = {
    compose: ImmutableMap<string, unknown>({
      is_uploading: false,
      progress: 0,
      is_processing: false,
    }),
  };
  const setAttachments = (count: number) => {
    state.compose = state.compose.set(
      'media_attachments',
      List(
        Array.from({ length: count }, (_, index) =>
          ImmutableMap({ id: String(index) }),
        ),
      ),
    );
  };
  select.mockImplementation((selector: (value: typeof state) => unknown) =>
    selector(state),
  );
  setAttachments(4);
  const { rerender } = render(<UploadForm />);

  for (const count of [4, 5, 16, 4]) {
    setAttachments(count);
    rerender(<UploadForm />);

    const warning = screen.queryByText(
      'Other servers may only show the first 4 attachments.',
    );
    expect(warning !== null).toBe(count > 4);
    expect(screen.getAllByTestId('attachment').length).toBe(count);
  }
});
