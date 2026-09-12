# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Personal emoji packs' do
  let(:category) { Fabricate(:custom_emoji_category) }
  let(:emoji) { Fabricate(:custom_emoji, category: category, shortcode: 'shared', disabled: false, visible_in_picker: true) }
  let(:uncollected) { Fabricate(:custom_emoji, category: category, shortcode: 'aardvark', disabled: false, visible_in_picker: true) }
  let(:public_pack) { Wxw::EmojiPack.create!(name: 'Site', custom_emoji_category: category, default_enabled: true) }
  let(:first_pack) { Wxw::EmojiPack.create!(name: 'Alpha', user: user) }
  let(:second_pack) { Wxw::EmojiPack.create!(name: 'Beta', user: user) }

  describe 'GET /api/v1/custom_emojis' do
    include_context 'with API authentication'

    before do
      public_pack
      first_pack.favorites.create!(custom_emoji: emoji)
      second_pack
      uncollected
    end

    it 'orders groups by number and emojis by shortcode, emitting each emoji once and omitting empty packs' do
      first_pack.favorites.create!(custom_emoji: Fabricate(:custom_emoji, category: category, shortcode: 'apple'))
      Fabricate(:custom_emoji, category: category, shortcode: 'zebra')

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.map { |row| row.slice('shortcode', 'category') }).to eq([
        { 'shortcode' => 'apple', 'category' => '1. Alpha' },
        { 'shortcode' => 'shared', 'category' => '1. Alpha' },
        { 'shortcode' => 'aardvark', 'category' => '2. Site' },
        { 'shortcode' => 'zebra', 'category' => '2. Site' },
      ])
    end

    it 'omits numbers without discarding the saved mixed pack order' do
      second_pack.favorites.create!(custom_emoji: Fabricate(:custom_emoji, category: category, shortcode: 'zzz'))
      user.settings[Wxw::EmojiPack::NUMBERED_KEY] = false
      user.settings[Wxw::EmojiPack::ORDER_KEY] = Wxw::EmojiPack.dump_ids([public_pack.id, second_pack.id, first_pack.id])
      user.update_column(:settings, user.settings)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark zzz shared))
      expect(response.parsed_body.pluck('category')).to eq(%w(Site Beta Alpha))
      expect(Wxw::EmojiPack.order_ids(user.reload)).to eq([public_pack.id, second_pack.id, first_pack.id])
    end

    it 'restores the original category when favorites are disabled and includes favorites without the original pack' do
      user.settings[Wxw::EmojiPack::PICKS_KEY] = Wxw::EmojiPack.dump_ids([public_pack.id])
      user.update_column(:settings, user.settings)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark shared))
      expect(response.parsed_body.pluck('category')).to eq(['1. Site', '1. Site'])

      user.settings[Wxw::EmojiPack::PICKS_KEY] = Wxw::EmojiPack.dump_ids([first_pack.id])
      user.update_column(:settings, user.settings)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(['shared'])
      expect(response.parsed_body.pluck('category')).to eq(['1. Alpha'])
    end

    it 'does not number the original pack after all its emojis have been collected' do
      first_pack.favorites.create!(custom_emoji: uncollected)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark shared))
      expect(response.parsed_body.pluck('category')).to eq(['1. Alpha', '1. Alpha'])
    end

    it 'exposes only site categories anonymously and cannot select another user\'s personal pack' do
      get api_v1_custom_emojis_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark shared))
      expect(response.parsed_body.pluck('category')).to eq(%w(Site Site))

      private_pack = Wxw::EmojiPack.create!(name: 'Secret', user: Fabricate(:user))
      private_pack.favorites.create!(custom_emoji: emoji)
      user.settings[Wxw::EmojiPack::PICKS_KEY] = Wxw::EmojiPack.dump_ids([private_pack.id, public_pack.id])
      user.update_column(:settings, user.settings)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark shared))
      expect(response.parsed_body.pluck('category')).to eq(['1. Site', '1. Site'])
    end

    it 'uses the default public pack order anonymously and sorts shortcodes within each pack' do
      other_category = Fabricate(:custom_emoji_category)
      Wxw::EmojiPack.create!(name: 'Zulu', custom_emoji_category: other_category, default_enabled: true, position: -1)
      Fabricate(:custom_emoji, category: other_category, shortcode: 'zzz')

      get api_v1_custom_emojis_path

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(zzz aardvark shared))
      expect(response.parsed_body.pluck('category')).to eq(%w(Zulu Site Site))
    end

    it 'returns only public categories for revoked and expired tokens' do
      [{ revoked_at: 1.minute.ago }, { revoked_at: nil, expires_in: 1, created_at: 1.hour.ago }].each do |attributes|
        token.update!(attributes)

        get api_v1_custom_emojis_path, headers: headers

        expect(response).to have_http_status(200)
        expect(response.parsed_body.pluck('shortcode')).to eq(%w(aardvark shared))
        expect(response.parsed_body.pluck('category')).to eq(%w(Site Site))
      end
    end

    it 'uses the signed-in user when a revoked token belongs to another user' do
      session_user = Fabricate(:user)
      session_pack = Wxw::EmojiPack.create!(name: 'Session', user: session_user)
      session_pack.favorites.create!(custom_emoji: emoji)
      sign_in session_user
      token.update!(revoked_at: 1.minute.ago)

      get api_v1_custom_emojis_path, headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(shared aardvark))
      expect(response.parsed_body.pluck('category')).to eq(['1. Session', '2. Site'])
    end

    it 'does not instantiate custom emojis for anonymous or authenticated 304 responses with or without favorites' do
      first_pack.update!(featured_emoji: emoji)
      public_pack.update!(featured_emoji: uncollected)
      other_token = Fabricate(:accessible_access_token, resource_owner_id: Fabricate(:user).id)

      [{}, { 'Authorization' => "Bearer #{other_token.token}" }, headers].each do |request_headers|
        get api_v1_custom_emojis_path, headers: request_headers
        expect(response).to have_http_status(200)
        etag = response.headers.fetch('ETag')
        instantiated = 0
        subscriber = lambda do |*args|
          payload = args.last
          instantiated += payload[:record_count] if payload[:class_name] == 'CustomEmoji'
        end

        ActiveSupport::Notifications.subscribed(subscriber, 'instantiation.active_record') do
          get api_v1_custom_emojis_path, headers: request_headers.merge('If-None-Match' => etag)
        end

        expect(response).to have_http_status(304)
        expect(instantiated).to eq(0)
      end
    end

    it 'changes the personal ETag for member updates, disabling, deletion and featured icon FK nullification' do
      another = Fabricate(:custom_emoji, category: category, shortcode: 'another')
      first_pack.favorites.create!(custom_emoji: another)
      icon = Fabricate(:custom_emoji, disabled: true, visible_in_picker: false)
      first_pack.update!(featured_emoji: icon)
      emoji.update_columns(updated_at: Time.utc(2026, 9, 12, 0, 0, 0, 123_456))
      get api_v1_custom_emojis_path, headers: headers
      etag = response.headers.fetch('ETag')

      [
        -> { emoji.update_columns(shortcode: 'renamed', updated_at: Time.utc(2026, 9, 12, 0, 0, 0, 123_457)) },
        -> { emoji.update!(disabled: true) },
        -> { icon.delete },
        -> { another.delete },
      ].each do |change|
        change.call
        get api_v1_custom_emojis_path, headers: headers.merge('If-None-Match' => etag)

        expect(response).to have_http_status(200)
        expect(response.headers.fetch('ETag')).to_not eq(etag)
        etag = response.headers.fetch('ETag')
      end

      expect(first_pack.reload.featured_emoji_id).to be_nil
      expect(response.parsed_body.pluck('shortcode')).to eq(['aardvark'])
    end

    it 'changes the personal ETag when membership moves while preserving the public version and anonymous ETag' do
      another = Fabricate(:custom_emoji, category: category, shortcode: 'another', disabled: false, visible_in_picker: true)
      membership = first_pack.favorites.create!(custom_emoji: another)
      public_version = Wxw::EmojiPack.publish_version
      get api_v1_custom_emojis_path
      anonymous_etag = response.headers.fetch('ETag')
      get api_v1_custom_emojis_path, headers: headers
      personal_etag = response.headers.fetch('ETag')
      get api_v1_custom_emojis_path, headers: headers.merge('If-None-Match' => personal_etag)
      expect(response).to have_http_status(304)

      membership.update!(pack: second_pack)
      get api_v1_custom_emojis_path, headers: headers.merge('If-None-Match' => personal_etag)

      expect(response).to have_http_status(200)
      expect(response.headers.fetch('ETag')).to_not eq(personal_etag)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(shared another aardvark))
      expect(response.parsed_body.find { |row| row['shortcode'] == 'another' }['category']).to eq('2. Beta')
      expect(Wxw::EmojiPack.publish_version).to eq(public_version)
      get api_v1_custom_emojis_path, headers: { 'If-None-Match' => anonymous_etag }
      expect(response).to have_http_status(304)
    end
  end

  describe 'personal management' do
    let(:user) { Fabricate(:user) }

    before { sign_in user }

    it 'enables favorites and public defaults without enabling other public packs' do
      public_pack
      first_pack.favorites.create!(custom_emoji: emoji)
      uncollected
      Wxw::EmojiPack.create!(name: 'Optional', custom_emoji_category: Fabricate(:custom_emoji_category))

      get settings_preferences_emoji_packs_path

      expect(response).to have_http_status(200)
      names = Nokogiri::HTML(response.body).css('.wxw-emoji-pack-list__name').map { |node| node.text.strip }
      expect(names).to eq(['1. Alpha', '2. Site', 'Optional'])
      expect(Wxw::EmojiPack.picked_ids(user.reload)).to be_nil
    end

    it 'keeps settings and API numbering aligned after restoring the management order' do
      public_pack
      first_pack.favorites.create!(custom_emoji: emoji)
      second_pack.favorites.create!(custom_emoji: Fabricate(:custom_emoji, category: category, shortcode: 'aaa'))
      Fabricate(:custom_emoji, category: category, shortcode: 'zzz')
      management_order = [first_pack.id, second_pack.id, public_pack.id]

      patch settings_preferences_emoji_packs_path, params: { save_order: '1', user: { emoji_order: management_order.reverse.map(&:to_s) } }
      expect(response).to redirect_to(settings_preferences_emoji_packs_path)
      patch settings_preferences_emoji_packs_path, params: { enable: '1', user: { emoji_ids: management_order.map(&:to_s) } }
      expect(response).to redirect_to(settings_preferences_emoji_packs_path)
      expect(Wxw::EmojiPack.picked_ids(user.reload)).to eq(management_order.reverse)
      patch settings_preferences_emoji_packs_path, params: { save_order: '1', user: { emoji_order: management_order.map(&:to_s) } }
      expect(response).to redirect_to(settings_preferences_emoji_packs_path)
      expect(Wxw::EmojiPack.order_ids(user.reload)).to eq(management_order)
      follow_redirect!

      names = Nokogiri::HTML(response.body).css('.wxw-emoji-pack-list__name').map { |node| node.text.strip }
      expect(names).to eq(['1. Alpha', '2. Beta', '3. Site'])
      expect(Nokogiri::HTML(response.body).at_css('button[name="save_order"]')).to be_present
      get api_v1_custom_emojis_path
      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck('shortcode')).to eq(%w(shared aaa zzz))
      expect(response.parsed_body.pluck('category')).to eq(names)
    end

    it 'uses the full default or saved pack order in search without moving collected or uncategorized emojis' do
      public_pack
      optional = Wxw::EmojiPack.create!(name: 'Optional', custom_emoji_category: Fabricate(:custom_emoji_category), position: 1)
      Fabricate(:custom_emoji, category: optional.custom_emoji_category, shortcode: 'zz_optional')
      Fabricate(:custom_emoji, shortcode: 'aa_uncategorized')
      second_pack
      first_pack.favorites.create!(custom_emoji: emoji)
      uncollected
      user.settings[Wxw::EmojiPack::PICKS_KEY] = Wxw::EmojiPack.dump_ids([first_pack.id, public_pack.id])

      [
        [nil, [first_pack.id, second_pack.id, public_pack.id, optional.id], %w(:aardvark: :shared: :zz_optional: :aa_uncategorized:)],
        [[optional.id, second_pack.id, public_pack.id, first_pack.id], [optional.id, second_pack.id, public_pack.id, first_pack.id], %w(:zz_optional: :aardvark: :shared: :aa_uncategorized:)],
      ].each do |order, expected_pack_ids, expected_labels|
        user.settings[Wxw::EmojiPack::ORDER_KEY] = order && Wxw::EmojiPack.dump_ids(order)
        user.update_column(:settings, user.settings)

        get search_settings_preferences_emoji_packs_path

        expect(response).to have_http_status(200)
        search = Nokogiri::HTML(response.body)
        expect(search.css('select[name="pack_id"] option').drop(2).map { |option| option['value'].to_i }).to eq(expected_pack_ids)
        expect(search.css('samp.wxw-emoji-picker__label').map { |label| label.text.strip }).to eq(expected_labels)
      end
    end

    it 'orders enabled favorites by their original public packs and preserves complete single-pack searches' do
      public_pack
      other = Wxw::EmojiPack.create!(name: 'Other', custom_emoji_category: Fabricate(:custom_emoji_category), position: 1)
      another = Fabricate(:custom_emoji, category: other.custom_emoji_category, shortcode: 'aaa_other')
      disabled = Fabricate(:custom_emoji, category: category, shortcode: 'disabled', disabled: true)
      [emoji, another, disabled].each { |member| first_pack.favorites.create!(custom_emoji: member) }
      uncollected
      user.settings[Wxw::EmojiPack::PICKS_KEY] = Wxw::EmojiPack.dump_ids([first_pack.id])
      user.update_column(:settings, user.settings)

      [
        ['0', %w(:shared: :aaa_other:)],
        [public_pack.id, %w(:aardvark: :shared:)],
        [first_pack.id, %w(:aaa_other: :disabled: :shared:)],
      ].each do |pack_id, expected_labels|
        get search_settings_preferences_emoji_packs_path, params: { pack_id: pack_id }

        expect(response).to have_http_status(200)
        expect(Nokogiri::HTML(response.body).css('samp.wxw-emoji-picker__label').map { |label| label.text.strip }).to eq(expected_labels)
      end
    end

    it 'orders search before pagination and retains listed emojis when no public packs exist' do
      allow(CustomEmoji).to receive(:default_per_page).and_return(2)
      public_pack
      other = Wxw::EmojiPack.create!(name: 'Other', custom_emoji_category: Fabricate(:custom_emoji_category), position: 1)
      Fabricate(:custom_emoji, category: other.custom_emoji_category, shortcode: 'aaa_other')
      Fabricate(:custom_emoji, shortcode: 'zz_uncategorized')
      emoji
      uncollected

      [
        [%w(:aardvark: :shared:), %w(:aaa_other: :zz_uncategorized:)],
        [%w(:aaa_other: :aardvark:), %w(:shared: :zz_uncategorized:)],
      ].each_with_index do |pages, index|
        Wxw::EmojiPack.public_packs.delete_all if index.positive?
        pages.each_with_index do |expected_labels, page|
          get search_settings_preferences_emoji_packs_path, params: { page: page + 1 }

          expect(response).to have_http_status(200)
          expect(Nokogiri::HTML(response.body).css('samp.wxw-emoji-picker__label').map { |label| label.text.strip }).to eq(expected_labels)
        end
      end
    end

    it 'refreshes only missing icons in the current user\'s packs using the first shortcode' do
      first_by_shortcode = Fabricate(:custom_emoji, shortcode: 'aaa')
      first_pack.favorites.create!(custom_emoji: first_by_shortcode)
      first_pack.favorites.create!(custom_emoji: emoji)
      existing_icon = Fabricate(:custom_emoji, disabled: true, visible_in_picker: false)
      second_pack.update!(featured_emoji: existing_icon)
      second_pack.favorites.create!(custom_emoji: Fabricate(:custom_emoji))
      empty_pack = Wxw::EmojiPack.create!(name: 'Empty', user: user)
      other_pack = Wxw::EmojiPack.create!(name: 'Other', user: Fabricate(:user))
      other_pack.favorites.create!(custom_emoji: emoji)
      untouched = [second_pack, empty_pack, other_pack, public_pack]
      original = untouched.map { |pack| pack.reload.attributes }

      get settings_preferences_emoji_favorites_path

      expect(response).to have_http_status(200)
      refresh_form = Nokogiri::HTML(response.body).at_css("form[action='#{refresh_icons_settings_preferences_emoji_favorites_path}']")
      expect(refresh_form['method']).to eq('post')
      expect(first_pack.reload.featured_emoji_id).to be_nil

      post refresh_icons_settings_preferences_emoji_favorites_path, params: { user_id: other_pack.user_id }

      expect(response).to redirect_to(settings_preferences_emoji_favorites_path)
      expect(first_pack.reload.featured_emoji_id).to eq(first_by_shortcode.id)
      expect(untouched.map { |pack| pack.reload.attributes }).to eq(original)

      first_pack.favorites.find_by!(custom_emoji: first_by_shortcode).destroy!
      refreshed = first_pack.reload.attributes
      post refresh_icons_settings_preferences_emoji_favorites_path

      expect(first_pack.reload.attributes).to eq(refreshed)
      expect(untouched.map { |pack| pack.reload.attributes }).to eq(original)
    end

    it 'creates a destination from an empty list, preserves pending choices and adds real shortcodes without choosing an icon' do
      manual = Fabricate(:custom_emoji, shortcode: 'manual')
      another = Fabricate(:custom_emoji, shortcode: 'another')
      shortcodes = ':manual:, another :shared:'
      pending = { emoji_ids: [emoji.id.to_s], shortcodes: shortcodes, operation: 'add', return_to_choose: '1' }

      get choose_settings_preferences_emoji_favorites_path, params: pending

      expect(response).to have_http_status(200)
      new_link = Nokogiri::HTML(response.body).at_css("a[href^='#{new_settings_preferences_emoji_favorite_path}']")
      expect(new_link).to be_present
      get new_link['href']

      expect(response).to have_http_status(200)
      form = Nokogiri::HTML(response.body)
      expect(form.at_css('input[name="emoji_ids[]"]')['value']).to eq(emoji.id.to_s)
      expect(form.at_css('input[name="shortcodes"]')['value']).to eq(shortcodes)

      post settings_preferences_emoji_favorites_path, params: pending.merge(wxw_emoji_pack: { name: 'My collection', featured_shortcode: '' })

      pack = Wxw::EmojiPack.find_by!(user: user, name: 'My collection')
      expect(response).to redirect_to(choose_settings_preferences_emoji_favorites_path(emoji_ids: [emoji.id], target_pack_id: pack.id, shortcodes: shortcodes))
      follow_redirect!

      expect(response).to have_http_status(200)
      form = Nokogiri::HTML(response.body)
      expect(form.at_css('input[name="emoji_ids[]"]')['value']).to eq(emoji.id.to_s)
      expect(form.at_css('select[name="target_pack_id"] option[selected]')['value']).to eq(pack.id.to_s)
      expect(form.at_css('textarea[name="shortcodes"]').text.strip).to eq(shortcodes)

      post apply_settings_preferences_emoji_favorites_path, params: pending.merge(target_pack_id: pack.id)

      expect(response).to redirect_to(search_settings_preferences_emoji_packs_path(pack_id: pack.id))
      expect(pack.favorites.pluck(:custom_emoji_id)).to contain_exactly(emoji.id, manual.id, another.id)
      expect(pack.reload.featured_emoji_id).to be_nil
      follow_redirect!

      expect(response).to have_http_status(200)
      search = Nokogiri::HTML(response.body)
      expect(search.css('samp.wxw-emoji-picker__label').map { |label| label.text.strip }).to eq(%w(:another: :manual: :shared:))
      expect(search.css('.batch-table__toolbar button').map { |button| button['name'] }).to eq(%w(add remove))
      expect(search.at_css("form[action='#{choose_settings_preferences_emoji_favorites_path}']")['method']).to eq('get')
      expect(search.at_css('input[name="target_pack_id"]')['value']).to eq(pack.id.to_s)
      expect(search.css('.wxw-sortable, [draggable], input[name="order[]"], input[name="visible_ids[]"]')).to be_empty
      search.css('.batch-table__toolbar button').each do |button|
        expect(button.at_css('svg path')).to be_present
      end

      [settings_preferences_emoji_favorites_path, settings_preferences_emoji_packs_path].each do |path|
        get path

        expect(response).to have_http_status(200)
        icons = Nokogiri::HTML(response.body).css('.wxw-emoji-pack-list__icon')
        expect(icons.size).to eq(1)
        expect(icons.css('img')).to be_empty
        expect(icons.css('svg.material-mood').size).to eq(1)
        next unless path == settings_preferences_emoji_favorites_path

        favorites = Nokogiri::HTML(response.body)
        expect(favorites.css('.wxw-sortable, [draggable], button[name="save_order"], input[name="order[]"]')).to be_empty
        expect(favorites.css('.wxw-emoji-pack-list__meta a').map { |link| link['href'] }).to eq([search_settings_preferences_emoji_packs_path(pack_id: pack.id)])
      end

      get edit_settings_preferences_emoji_favorite_path(pack)

      expect(response).to have_http_status(200)
      form = Nokogiri::HTML(response.body)
      expect(form.at_css('input[name="wxw_emoji_pack[name]"]')['value']).to eq('My collection')
      expect(form.at_css('input[name="wxw_emoji_pack[featured_shortcode]"]')['value']).to be_blank
    end

    it 'saves a custom name and an unrelated disabled icon, then displays a placeholder after that emoji is deleted' do
      first_pack.favorites.create!(custom_emoji: emoji)
      icon = Fabricate(:custom_emoji, shortcode: 'outside_icon', disabled: true, visible_in_picker: false)

      patch settings_preferences_emoji_favorite_path(first_pack), params: { wxw_emoji_pack: { name: 'Renamed freely', featured_shortcode: ':outside_icon:' } }

      expect(response).to redirect_to(settings_preferences_emoji_favorites_path)
      expect(first_pack.reload).to have_attributes(name: 'Renamed freely', featured_emoji_id: icon.id)
      follow_redirect!

      expect(response).to have_http_status(200)
      expect(Nokogiri::HTML(response.body).at_css('.wxw-emoji-pack-list__icon img')['alt']).to eq(':outside_icon:')

      icon.delete
      get settings_preferences_emoji_favorites_path

      expect(response).to have_http_status(200)
      expect(first_pack.reload.featured_emoji_id).to be_nil
      frame = Nokogiri::HTML(response.body).at_css('.wxw-emoji-pack-list__icon')
      expect(frame.css('img')).to be_empty
      expect(frame.at_css('svg.material-mood')).to be_present
      expect(first_pack.favorites.pluck(:custom_emoji_id)).to eq([emoji.id])
    end

    it 'renders selection errors without adding members for empty input or any unknown manual shortcode' do
      post apply_settings_preferences_emoji_favorites_path, params: { target_pack_id: first_pack.id, operation: 'add', shortcodes: '' }

      expect(response).to have_http_status(422)
      expect(Nokogiri::HTML(response.body).at_css('.flash-message.alert')).to be_present
      expect(first_pack.favorites).to be_empty

      shortcodes = ':shared: :does_not_exist:'
      emoji
      post apply_settings_preferences_emoji_favorites_path, params: { target_pack_id: first_pack.id, operation: 'add', shortcodes: shortcodes }

      expect(response).to have_http_status(422)
      form = Nokogiri::HTML(response.body)
      expect(form.at_css('.flash-message.alert').text).to include('does_not_exist')
      expect(form.at_css('textarea[name="shortcodes"]').text.strip).to eq(shortcodes)
      expect(first_pack.favorites.reload).to be_empty
    end

    it 'rejects direct edits and member removals on another user\'s pack' do
      private_pack = Wxw::EmojiPack.create!(name: 'Secret', user: Fabricate(:user))
      member = private_pack.favorites.create!(custom_emoji: emoji)

      patch settings_preferences_emoji_favorite_path(private_pack), params: { wxw_emoji_pack: { name: 'Changed' } }

      expect(response).to have_http_status(404)
      expect(private_pack.reload.name).to eq('Secret')

      post apply_settings_preferences_emoji_favorites_path, params: { target_pack_id: private_pack.id, operation: 'remove', emoji_ids: [emoji.id.to_s] }

      expect(response).to have_http_status(404)
      expect(Wxw::EmojiFavorite.exists?(member.id)).to be true
    end

    it 'moves an existing membership without duplicates or changes to another user\'s collection' do
      membership = first_pack.favorites.create!(custom_emoji: emoji)
      private_pack = Wxw::EmojiPack.create!(name: 'Private', user: Fabricate(:user))
      private_membership = private_pack.favorites.create!(custom_emoji: emoji)
      private_attributes = private_membership.attributes
      destination = second_pack

      2.times do
        expect do
          post apply_settings_preferences_emoji_favorites_path, params: { target_pack_id: destination.id, operation: 'add', emoji_ids: [emoji.id.to_s] }
        end.to_not change(Wxw::EmojiFavorite, :count)

        expect(response).to redirect_to(search_settings_preferences_emoji_packs_path(pack_id: destination.id))
        expect(membership.reload).to have_attributes(pack_id: destination.id, user_id: user.id)
        expect(first_pack.favorites.reload).to be_empty
        expect(destination.favorites.reload.ids).to eq([membership.id])
        expect(private_membership.reload.attributes).to eq(private_attributes)
      end

      post apply_settings_preferences_emoji_favorites_path, params: { target_pack_id: destination.id, operation: 'remove', emoji_ids: [emoji.id.to_s] }

      expect(response).to redirect_to(search_settings_preferences_emoji_packs_path(pack_id: destination.id))
      expect(Wxw::EmojiFavorite.exists?(membership.id)).to be false
      expect(private_membership.reload.attributes).to eq(private_attributes)
    end

    it 'rejects obsolete favorite sorting submissions without changing the saved pack order' do
      order = Wxw::EmojiPack.dump_ids([first_pack.id, second_pack.id])
      user.settings[Wxw::EmojiPack::ORDER_KEY] = order
      user.update_column(:settings, user.settings)

      post batch_settings_preferences_emoji_favorites_path, params: { save_order: '1', order: [second_pack.id.to_s, first_pack.id.to_s] }

      expect(response).to have_http_status(400)
      expect(user.reload.settings[Wxw::EmojiPack::ORDER_KEY]).to eq(order)
    end
  end
end
