import {
  wxwNormalizeRemoteVisibility,
  wxwRemoteVisibilityAllowed,
} from './visibility';

export const postingDefaultsVisibilitySelector =
  '#user_settings_attributes_default_privacy, #user_settings_attributes_wxw_default_remote_privacy';

export const getPostingDefaultsQuoteVisibility = (
  changedSelect: HTMLSelectElement,
): string => {
  const privacySelect = changedSelect.form?.querySelector<HTMLSelectElement>(
    '#user_settings_attributes_default_privacy',
  );
  if (!privacySelect) return changedSelect.value;

  const remoteSelect = changedSelect.form?.querySelector<HTMLSelectElement>(
    '#user_settings_attributes_wxw_default_remote_privacy',
  );
  if (remoteSelect) {
    if (
      changedSelect === privacySelect &&
      remoteSelect.dataset.wxwOverride !== 'true'
    ) {
      remoteSelect.value = privacySelect.value;
    }
    const override = wxwNormalizeRemoteVisibility(
      privacySelect.value,
      remoteSelect.value,
    );
    remoteSelect.value = override ?? privacySelect.value;
    remoteSelect.dataset.wxwOverride = String(override !== null);
    for (const option of remoteSelect.options) {
      option.disabled = !wxwRemoteVisibilityAllowed(
        privacySelect.value,
        option.value,
      );
    }
  }

  const visibilities = [privacySelect.value, remoteSelect?.value];
  return (
    visibilities.find((value) => value === 'private' || value === 'direct') ??
    (visibilities.includes('unlisted') ? 'unlisted' : 'public')
  );
};
