# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Remote image limits' do
  [
    [:custom_emoji, :image, 256.kilobytes, 2.megabytes],
    [:account, :avatar, 8.megabytes, 16.megabytes],
    [:account, :header, 8.megabytes, 16.megabytes],
  ].each do |fabricator, attachment, local_limit, remote_limit|
    describe "#{fabricator} #{attachment}" do
      let(:record) { Fabricate.build(fabricator, domain: domain) }
      let(:domain) { 'remote.example' }
      let(:url) { "https://remote.example/#{attachment}.png" }

      { local: [nil, local_limit], remote: ['remote.example', remote_limit] }.each do |origin, (domain, limit)|
        context "when #{origin}" do
          let(:domain) { domain }

          it 'validates the appropriate size boundary' do
            record.public_send(:"#{attachment}=", attachment_fixture('emojo.png'))
            record.public_send(:"#{attachment}_file_size=", limit - 1)

            expect(record).to be_valid

            record.public_send(:"#{attachment}_file_size=", limit + 1)

            expect(record).to_not be_valid
            expect(record.errors[:"#{attachment}_file_size"]).to be_present
          end
        end
      end

      it 'downloads and accepts files above the local limit up to the remote boundary' do
        stub_request(:get, url).to_return(body: padded_image(remote_limit - 1))

        record.public_send(:"#{attachment}_remote_url=", url)

        expect(record.public_send(:"#{attachment}_file_size")).to eq(remote_limit - 1)
        expect(record).to be_valid
        expect(a_request(:get, url)).to have_been_made.once
      end

      it 'rejects an oversized download even without Content-Length' do
        stub_request(:get, url).to_return(body: padded_image(remote_limit + 1))

        record.public_send(:"#{attachment}_remote_url=", url)

        expect(record.public_send(attachment)).to be_blank
        expect(a_request(:get, url)).to have_been_made.once
      end
    end
  end

  it 'keeps copied remote emoji within the local upload limit' do
    emoji = Fabricate.build(:custom_emoji, domain: 'remote.example')
    url = 'https://remote.example/emoji.png'
    stub_request(:get, url).to_return(body: padded_image(256.kilobytes + 1))
    emoji.image_remote_url = url
    emoji.save!

    expect { emoji.copy! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(CustomEmoji.local.where(shortcode: emoji.shortcode)).to be_empty
  end

  def padded_image(size)
    Rails.root.join('spec', 'fixtures', 'files', 'emojo.png').binread.ljust(size, "\0")
  end
end
