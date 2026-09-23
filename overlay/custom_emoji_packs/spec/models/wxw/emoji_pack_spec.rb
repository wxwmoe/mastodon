# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wxw::EmojiPack do
  let(:user) { Fabricate(:user) }
  let(:category) { Fabricate(:custom_emoji_category) }
  let(:public_pack) { described_class.create!(name: 'Site', custom_emoji_category: category, default_enabled: true) }

  it 'uses the module tables for every emoji model' do
    models = [described_class, Wxw::EmojiSection, Wxw::EmojiFavorite, Wxw::EmojiTranslation]

    expect(models.map(&:table_name)).to eq(%w(wxw_emoji_packs wxw_emoji_sections wxw_emoji_favorites wxw_emoji_translations))
  end

  describe 'personal selection' do
    it 'keeps unset preferences unset and sorts newly created favorites alphabetically before defaults' do
      public_pack
      zebra = described_class.create!(name: 'Zebra', user: user)
      alpha = described_class.create!(name: 'alpha', user: user)

      expect(described_class.picked_ids(user.reload)).to be_nil
      expect(described_class.order_ids(user)).to be_nil
      expect(described_class.selection_for(user)).to eq([alpha, zebra, public_pack])
      expect(alpha.name_for(:ja)).to eq('alpha')
    end

    it 'enables only the new favorite after an explicitly empty selection' do
      public_pack
      described_class.create!(name: 'Existing', user: user)
      user.settings[described_class::PICKS_KEY] = '[]'
      user.settings[described_class::ORDER_KEY] = '[]'
      user.update_column(:settings, user.settings)

      added = described_class.create!(name: 'New', user: user)

      expect(described_class.picked_ids(user.reload)).to eq([added.id])
      expect(described_class.order_ids(user)).to eq([added.id])
      expect(described_class.selection_for(user)).to eq([added])
    end

    it 'honors mixed saved ordering and discards another user\'s pack IDs' do
      own = described_class.create!(name: 'Mine', user: user)
      other = described_class.create!(name: 'Private', user: Fabricate(:user))
      user.settings[described_class::PICKS_KEY] = described_class.dump_ids([own.id, other.id, public_pack.id])
      user.settings[described_class::ORDER_KEY] = described_class.dump_ids([other.id, public_pack.id, own.id])

      expect(described_class.selection_for(user)).to eq([public_pack, own])
      expect(described_class.management_packs(user)).to contain_exactly(own, public_pack)
      expect(described_class.default_selection).to eq([public_pack])
    end
  end

  describe '.refresh!' do
    it 'continues importing when another refresh creates a pack before uniqueness validation' do
      category
      later_category = Fabricate(:custom_emoji_category)
      allow(described_class).to receive(:transaction).and_wrap_original do |transaction, **options, &block|
        # The competing insert becomes visible after enumeration, before the savepoint.
        public_pack if options[:requires_new]
        transaction.call(**options, &block)
      end

      described_class.refresh!

      expect(described_class.public_packs.where(custom_emoji_category_id: category.id)).to contain_exactly(public_pack)
      expect(described_class.public_packs.exists?(custom_emoji_category_id: later_category.id)).to be true
    end

    it 'does not hide other validation failures when the category has a competing pack' do
      category
      allow(described_class).to receive(:transaction).and_wrap_original do |transaction, **options, &block|
        public_pack if options[:requires_new]
        transaction.call(**options, &block)
      end
      allow(described_class).to receive(:create!).and_wrap_original do |create, **attributes|
        create.call(**attributes.merge(name: attributes[:position] ? '' : attributes[:name]))
      end

      expect { described_class.refresh! }.to raise_error(ActiveRecord::RecordInvalid) do |error|
        expect(error.record.errors).to be_of_kind(:name, :blank)
        expect(error.record.errors).to be_of_kind(:custom_emoji_category_id, :taken)
      end
    end

    it 'assigns category icons before shortcode fallbacks without changing personal packs' do
      first = Fabricate(:custom_emoji, category: category, shortcode: 'aaa')
      category_icon = Fabricate(:custom_emoji, category: category, shortcode: 'zzz')
      category.update!(featured_emoji: category_icon)
      personal = described_class.create!(name: 'Mine', user: user)
      personal.favorites.create!(custom_emoji: first)
      personal.favorites.create!(custom_emoji: category_icon)
      personal_attributes = personal.reload.attributes

      expect(described_class.icon_emojis_for([public_pack, personal]).values).to eq([nil, nil])

      described_class.refresh!

      expect(public_pack.reload.featured_emoji).to eq(category_icon)
      expect(personal.reload.attributes).to eq(personal_attributes)

      category.update!(featured_emoji: first)
      personal.favorites.find_by!(custom_emoji: category_icon).destroy!
      personal_attributes = personal.reload.attributes
      described_class.refresh!

      expect(public_pack.reload.featured_emoji).to eq(category_icon)
      expect(personal.reload.attributes).to eq(personal_attributes)
    end

    it 'leaves empty packs empty and fills only public icons on a later refresh' do
      public_pack
      personal = described_class.create!(name: 'Mine', user: user)
      described_class.refresh!

      expect(public_pack.reload.featured_emoji_id).to be_nil
      expect(personal.reload.featured_emoji_id).to be_nil

      later = Fabricate(:custom_emoji, category: category, shortcode: 'zzz')
      first = Fabricate(:custom_emoji, category: category, shortcode: 'aaa')
      personal.favorites.create!(custom_emoji: later)
      described_class.refresh!

      expect(public_pack.reload.featured_emoji).to eq(first)
      expect(personal.reload.featured_emoji_id).to be_nil
    end

    it 'keeps explicitly selected hidden or disabled icons outside the pack until their emoji is deleted' do
      icon = Fabricate(:custom_emoji, shortcode: 'external_icon', disabled: true, visible_in_picker: false)
      member = Fabricate(:custom_emoji)
      personal = described_class.create!(name: 'Mine', user: user, featured_shortcode: ':external_icon:')
      personal.favorites.create!(custom_emoji: member)
      public_pack.update!(featured_shortcode: 'external_icon')
      described_class.refresh!

      expect(personal.reload.featured_emoji).to eq(icon)
      expect(public_pack.reload.featured_emoji).to eq(icon)

      icon.delete # Exercise the database FK without model callbacks.

      expect(personal.reload.featured_emoji_id).to be_nil
      expect(public_pack.reload.featured_emoji_id).to be_nil
      expect(described_class.icon_emojis_for([personal])).to eq(personal.id => nil)

      described_class.refresh!

      expect(personal.reload.featured_emoji_id).to be_nil
      expect(public_pack.reload.featured_emoji_id).to be_nil

      described_class.favorites.where(user_id: user.id).refresh_icons!

      expect(personal.reload.featured_emoji).to eq(member)
    end

    it 'cleans only permanently unavailable users and preserves their unrelated preferences' do
      permanent = user
      temporary = Fabricate(:user)
      disabled = Fabricate(:user, disabled: true)
      permanent.account.update!(suspended_at: 40.days.ago)
      temporary.account.update!(suspended_at: 40.days.ago)
      temporary.account.create_deletion_request!
      owners = [permanent, temporary, disabled]
      packs = owners.map { |owner| described_class.create!(name: 'Mine', user: owner) }
      member = packs.first.favorites.create!(custom_emoji: Fabricate(:custom_emoji))
      owners.zip(packs).each do |owner, pack|
        owner.settings[described_class::PICKS_KEY] = described_class.dump_ids([pack.id])
        owner.settings[described_class::ORDER_KEY] = described_class.dump_ids([pack.id])
        owner.settings[described_class::NUMBERED_KEY] = false
        owner.settings['web.reduce_motion'] = true
        owner.update_column(:settings, owner.settings)
      end

      expect(described_class.refresh!).to eq(users: 1, packs: 1)

      expect(described_class.exists?(packs.first.id)).to be false
      expect(Wxw::EmojiFavorite.exists?(member.id)).to be false
      expect(permanent.reload.settings['web.reduce_motion']).to be true
      expect(permanent.settings.as_json.stringify_keys.keys).to_not include(described_class::PICKS_KEY, described_class::ORDER_KEY, described_class::NUMBERED_KEY)
      owners.drop(1).zip(packs.drop(1)).each do |owner, pack|
        expect(described_class.exists?(pack.id)).to be true
        expect(described_class.picked_ids(owner.reload)).to eq([pack.id])
        expect(described_class.order_ids(owner)).to eq([pack.id])
        expect(described_class.numbered?(owner)).to be false
      end
      expect(described_class.refresh!).to eq(users: 0, packs: 0)
    end
  end

  describe 'database ownership constraints' do
    it 'enforces one membership per user and emoji while allowing different users to collect the same emoji' do
      emoji = Fabricate(:custom_emoji)
      first = described_class.create!(name: 'First', user: user)
      second = described_class.create!(name: 'Second', user: user)
      other = described_class.create!(name: 'Other', user: Fabricate(:user))
      membership = first.favorites.create!(custom_emoji: emoji)
      other_membership = other.favorites.create!(custom_emoji: emoji)

      expect(membership.user_id).to eq(user.id)
      expect(other_membership.user_id).to eq(other.user_id)
      expect(second.favorites.build(custom_emoji: emoji)).to_not be_valid
      expect do
        Wxw::EmojiFavorite.transaction(requires_new: true) do
          Wxw::EmojiFavorite.insert_all!([{ user_id: user.id, pack_id: second.id, custom_emoji_id: emoji.id }])
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'cascades user deletion through packs and memberships without deleting the emoji' do
      emoji = Fabricate(:custom_emoji)
      pack = described_class.create!(name: 'Mine', user: user)
      member = pack.favorites.create!(custom_emoji: emoji)

      user.delete

      expect(described_class.exists?(pack.id)).to be false
      expect(Wxw::EmojiFavorite.exists?(member.id)).to be false
      expect(CustomEmoji.exists?(emoji.id)).to be true
    end
  end
end
