# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Remote visibility federation' do
  let(:author) { Fabricate(:account) }
  let(:local_reader) { Fabricate(:account) }
  let(:remote_reader) { Fabricate(:account, protocol: :activitypub, domain: 'reader.example', inbox_url: 'https://reader.example/inbox') }
  let(:remote_follower) { Fabricate(:account, protocol: :activitypub, domain: 'follower.example', inbox_url: 'https://follower.example/inbox') }
  let(:remote_mentioned) { Fabricate(:account, protocol: :activitypub, domain: 'mentioned.example', inbox_url: 'https://mentioned.example/inbox') }
  let(:tag_manager) { ActivityPub::TagManager.instance }

  %w(public unlisted private direct).product(%w(public unlisted private direct)).each do |local_visibility, remote_visibility|
    context "with #{local_visibility} local and #{remote_visibility} remote visibility" do
      let(:status) { Fabricate(:status, account: author, visibility: local_visibility, wxw_remote_visibility: remote_visibility) }
      let(:effective_visibility) { [local_visibility, remote_visibility].max_by { |value| Status.visibilities.fetch(value) } }

      before do
        remote_follower.follow!(author)
        status.mentions.create!(account: remote_mentioned)
      end

      it 'keeps federated access at least as restrictive as local access' do
        expect(StatusPolicy.new(nil, status).show?).to eq(%w(public unlisted).include?(local_visibility))
        expect(StatusPolicy.new(local_reader, status).show?).to eq(%w(public unlisted).include?(local_visibility))
        expect(StatusPolicy.new(nil, status, federation: true).show?).to eq(%w(public unlisted).include?(effective_visibility))
        expect(StatusPolicy.new(remote_reader, status).show?).to eq(%w(public unlisted).include?(effective_visibility))
        expect(StatusPolicy.new(remote_follower, status).show?).to eq(effective_visibility != 'direct')
        expect(StatusPolicy.new(remote_mentioned, status).show?).to be true
      end

      it 'uses the remote value for ActivityPub addressing and signatures' do
        expected_to = case effective_visibility
                      when 'public'
                        [ActivityPub::TagManager::COLLECTIONS[:public]]
                      when 'unlisted', 'private'
                        [tag_manager.followers_uri_for(author)]
                      else
                        [tag_manager.uri_for(remote_mentioned)]
                      end

        expect(tag_manager.to(status)).to eq(expected_to)
        expect(tag_manager.cc(status).include?(ActivityPub::TagManager::COLLECTIONS[:public])).to eq(effective_visibility == 'unlisted')
        expect(status.sign?).to eq(%w(public unlisted).include?(effective_visibility))
      end
    end
  end

  context 'with a public local post restricted remotely' do
    let(:status) { Fabricate(:status, account: author, visibility: :public, wxw_remote_visibility: :private) }
    let!(:relay) { Fabricate(:relay, state: :accepted) }

    before do
      remote_follower.follow!(author)
      status.mentions.create!(account: remote_mentioned)
      status.favourites.create!(account: remote_reader)
    end

    it 'does not send to a relay or a non-follower who only interacted with the local public copy' do
      expect(StatusReachFinder.new(status).inboxes).to contain_exactly(remote_follower.inbox_url, remote_mentioned.inbox_url)
    end

    it 'sends a direct override only to its mentions' do
      status.update!(wxw_remote_visibility: :direct)
      expect(StatusReachFinder.new(status).inboxes).to contain_exactly(remote_mentioned.inbox_url)
    end

    it 'keeps other users local boosts local without changing native boost permission' do
      expect(StatusPolicy.new(local_reader, status).reblog?).to be true
      reblog = ReblogService.new.call(local_reader, status, visibility: :public)

      expect(reblog.visibility).to eq('public')
      expect(reblog.wxw_federatable?).to be false
      expect(StatusPolicy.new(nil, reblog).show?).to be true
      expect(StatusPolicy.new(nil, reblog, federation: true).show?).to be false
      expect(StatusReachFinder.new(reblog).inboxes).to be_empty
      expect(StatusReachFinder.new(reblog, unsafe: true).inboxes).to be_empty
    end

    it 'keeps an authors own boost within their remote followers' do
      reblog = ReblogService.new.call(author, status, visibility: :public)

      expect(reblog.visibility).to eq('public')
      expect(reblog.wxw_effective_remote_visibility).to eq('private')
      expect(reblog.wxw_federatable?).to be true
      expect(StatusReachFinder.new(reblog).inboxes).to contain_exactly(remote_follower.inbox_url)
      expect(ActivityPub::AnnounceNoteSerializer.new(reblog).virtual_object).to eq(status)
      expect(tag_manager.to(reblog)).to eq([tag_manager.followers_uri_for(author)])
      expect(StatusPolicy.new(nil, reblog, federation: true).show?).to be false
    end

    it 'keeps even the authors own boost local when the remote audience is direct' do
      status.update!(wxw_remote_visibility: :direct)
      reblog = ReblogService.new.call(author, status, visibility: :public)

      expect(reblog.wxw_federatable?).to be false
      expect(StatusReachFinder.new(reblog).inboxes).to be_empty
    end

    it 'checks access before accepting an incoming remote like' do
      json = { 'id' => 'https://reader.example/likes/1', 'type' => 'Like', 'object' => tag_manager.uri_for(status) }
      status.favourites.where(account: remote_reader).delete_all

      expect { ActivityPub::Activity::Like.new(json, remote_reader).perform }.to_not change(Favourite, :count)
      expect { ActivityPub::Activity::Like.new(json, remote_follower).perform }.to change(Favourite, :count).by(1)
    end

    it 'checks remote permissions before accepting an announce of a local original' do
      activity = ActivityPub::Activity::Announce.new({}, remote_follower)
      expect(activity.send(:announceable?, status)).to be false

      status.update!(wxw_remote_visibility: :unlisted)
      expect(activity.send(:announceable?, status)).to be true
    end

    it 'checks access before accepting an incoming poll vote' do
      poll = Fabricate(:poll, account: author, status: status)
      status.update!(poll_id: poll.id)
      json = { 'object' => { 'id' => 'https://reader.example/votes/1', 'inReplyTo' => tag_manager.uri_for(status), 'name' => poll.options.first } }

      expect { ActivityPub::Activity::Create.new(json, remote_reader).send(:poll_vote?) }.to_not change(PollVote, :count)
      expect { ActivityPub::Activity::Create.new(json, remote_follower).send(:poll_vote?) }.to change(PollVote, :count).by(1)
    end

    it 'keeps poll updates within the remote audience' do
      poll = Fabricate(:poll, account: author, status: status)
      status.update!(poll_id: poll.id, wxw_remote_visibility: :direct)
      Fabricate(:poll_vote, poll: poll, account: remote_reader)

      ActivityPub::DistributePollUpdateWorker.new.perform(status.id)

      expect(ActivityPub::DeliveryWorker).to have_enqueued_sidekiq_job(anything, author.id, remote_mentioned.inbox_url)
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job(anything, author.id, remote_follower.inbox_url)
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job(anything, author.id, remote_reader.inbox_url)
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job(anything, author.id, relay.inbox_url)
    end
  end

  %w(private direct).each do |visibility|
    it "rejects incoming public boosts of a locally #{visibility} original with a legacy wider override" do
      status = Fabricate(:status, account: author, visibility: visibility)
      WxwStatusSetting.insert!({ status_id: status.id, settings: { 'remote_visibility' => 0 } })
      local_reader.follow!(remote_reader)
      json = {
        'id' => "#{remote_reader.uri}/announces/#{status.id}",
        'type' => 'Announce',
        'actor' => remote_reader.uri,
        'object' => tag_manager.uri_for(status),
        'to' => [ActivityPub::TagManager::COLLECTIONS[:public]],
      }

      expect { ActivityPub::Activity::Announce.new(json, remote_reader).perform }.to_not change(Status, :count)
      expect(StatusPolicy.new(local_reader, status).show?).to be false
      expect(StatusPolicy.new(remote_reader, status, federation: true).reblog?).to be false
    end
  end

  it 'retains native boost federation when no remote override exists' do
    status = Fabricate(:status, account: author, visibility: :public)
    reblog = ReblogService.new.call(local_reader, status, visibility: :public)

    expect(reblog.wxw_remote_visibility).to be_nil
    expect(reblog.wxw_federatable?).to be true
    expect(StatusPolicy.new(nil, reblog, federation: true).show?).to be true
  end
end
