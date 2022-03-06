FROM tootsuite/mastodon:v3.4.6

COPY --chown=991:991 ./chewy /opt/mastodon/app/chewy
#COPY --chown=991:991 ./media_cli.rb /opt/mastodon/lib/mastodon/media_cli.rb

RUN echo "修改字数上限" \
  && sed -i "s|MAX_CHARS = 500|MAX_CHARS = 20000|" /opt/mastodon/app/validators/status_length_validator.rb \
  && sed -i "s|length(fulltext) > 500|length(fulltext) > 20000|" /opt/mastodon/app/javascript/mastodon/features/compose/components/compose_form.js \
  && sed -i "s|CharacterCounter max={500}|CharacterCounter max={20000}|" /opt/mastodon/app/javascript/mastodon/features/compose/components/compose_form.js \
  && echo "修改媒体上限" \
  && sed -i "s|MAX_IMAGE_PIXELS = 2073600|MAX_IMAGE_PIXELS = 9999999|" /opt/mastodon/app/javascript/mastodon/utils/resize_image.js \
  && sed -i "s|pixels: 2_073_600|pixels: 9_999_999|" /opt/mastodon/app/models/media_attachment.rb \
  && sed -i "s|IMAGE_LIMIT = 10|IMAGE_LIMIT = 80|" /opt/mastodon/app/models/media_attachment.rb \
  && sed -i "s|VIDEO_LIMIT = 40|VIDEO_LIMIT = 100|" /opt/mastodon/app/models/media_attachment.rb \
  && echo "修改投票上限" \
  && sed -i "s|options.size >= 4|options.size >= 16|" /opt/mastodon/app/javascript/mastodon/features/compose/components/poll_form.js \
  && sed -i "s|MAX_OPTIONS      = 4|MAX_OPTIONS      = 16|" /opt/mastodon/app/validators/poll_validator.rb \
  && echo "修改客户端 API" \
  && sed -i "s|:settings|:settings, :max_toot_chars|" /opt/mastodon/app/serializers/initial_state_serializer.rb \
  && sed -i "s|private|def max_toot_chars\n    StatusLengthValidator::MAX_CHARS\n  end\n\n  private|" /opt/mastodon/app/serializers/initial_state_serializer.rb \
  && sed -i "s|:invites_enabled|:invites_enabled, :max_toot_chars|" /opt/mastodon/app/serializers/rest/instance_serializer.rb \
  && sed -i "s|private|def max_toot_chars\n    StatusLengthValidator::MAX_CHARS\n  end\n\n  private|" /opt/mastodon/app/serializers/rest/instance_serializer.rb \
  && echo "隐藏非目录用户" \
  && sed -i "s|if user_signed_in? && @account\.blocking?(current_account)|if !@account.discoverable \&\& \!user_signed_in?\n        \.nothing-here\.nothing-here--under-tabs= 'For wxw\.moe members only, you need login to view it\.'\n      - elsif user_signed_in? \&\& @account\.blocking?(current_account)|" /opt/mastodon/app/views/accounts/show.html.haml \
  && sed -i "s|^|  |" /opt/mastodon/app/views/statuses/show.html.haml \
  && sed -i "1i\- if !@account\.discoverable && \!user_signed_in?\n  - content_for :page_title do\n    = 'Access denied'\n\n  - content_for :header_tags do\n    - if @account\.user&\.setting_noindex\n      %meta{ name: 'robots', content: 'noindex, noarchive' }/\n\n    %link{ rel: 'alternate', type: 'application/json+oembed', href: api_oembed_url(url: short_account_status_url(@account, @status), format: 'json') }/\n    %link{ rel: 'alternate', type: 'application/activity+json', href: ActivityPub::TagManager\.instance\.uri_for(@status) }/\n\n  \.grid\n    \.column-0\n      \.activity-stream\.h-entry\n        \.entry\.entry-center\n          \.detailed-status\.detailed-status--flex\n            \.status__content\.emojify\n              \.e-content\n                = 'Access denied'\n            \.detailed-status__meta\n              = 'For wxw\.moe members only, you need login to view it\.'\n    \.column-1\n      = render 'application/sidebar'\n\n- else" /opt/mastodon/app/views/statuses/show.html.haml \
  && echo "允许站长查看私信" \
  && sed -i "s|@statuses = @account\.statuses\.where(visibility: \[:public, :unlisted\])|if @current_account.username == 'fghrsh'\n        @statuses = @account\.statuses\n      else\n        @statuses = @account\.statuses\.where(visibility: \[:public, :unlisted\])\n      end|" /opt/mastodon/app/controllers/admin/statuses_controller.rb \
  && echo "修改版本项目地址" \
  && sed -i "/def suffix/{n;s|''|'~wxw'|}" /opt/mastodon/lib/mastodon/version.rb \
  && sed -i "s|mastodon/mastodon|wxwmoe/mastodon|" /opt/mastodon/lib/mastodon/version.rb \
  && echo "重新编译资源文件" \
  && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile \
  && yarn cache clean
