#!/bin/bash
set -e

model="src/app/models/user_invite_request.rb"
locale="config/locales/wxw_registration_reason_dedup.yml"
validation='  validates :text, uniqueness: { conditions: -> { joins(:user).merge(User.pending) } }, allow_blank: true, on: :create'

test "$(grep -Fxc '  validates :text, presence: true, length: { maximum: TEXT_SIZE_LIMIT }' "$model")" -eq 1
test "$(grep -Fxc "$validation" "$model")" -eq 0
test ! -e "src/$locale"
test -f "overlay/registration_reason_dedup/$locale"

sed -i "/^  validates :text, presence: true, length: { maximum: TEXT_SIZE_LIMIT }$/a\\$validation" "$model"
grep -Fqx "$validation" "$model"
cp "overlay/registration_reason_dedup/$locale" "src/$locale"
