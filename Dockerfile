FROM tootsuite/mastodon:v4.1.4

COPY --chown=991:991 ./icons /opt/mastodon/app/javascript/icons
COPY --chown=991:991 ./images /opt/mastodon/app/javascript/images

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
  && echo "加入 No-More-Sidebar-in-Mastodon-4.0 样式" \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-no-more-sidebar \
  && wget -nv https://raw.githubusercontent.com/AkazaRenn/No-More-Sidebar-in-Mastodon-4.0/main/css/bottombar.css -O /opt/mastodon/app/javascript/styles/mastodon-no-more-sidebar/bottombar.scss \
  && echo -e "@import 'application';\n@import 'mastodon-no-more-sidebar/bottombar';" > /opt/mastodon/app/javascript/styles/mastodon-dark.scss \
  && echo -e "@import 'mastodon-no-more-sidebar/bottombar';" >> /opt/mastodon/app/javascript/styles/contrast.scss \
  && echo -e "@import 'mastodon-no-more-sidebar/bottombar';" >> /opt/mastodon/app/javascript/styles/mastodon-light.scss \
  && sed -i "s|application|mastodon-dark|" /opt/mastodon/config/themes.yml \
  && echo "加入 Mastodon (Sakura) 主题" \
  && sed -i "s|#6364FF|#f596aa|" /opt/mastodon/app/views/layouts/application.html.haml \
  && sed -i "s|#191b22|#fedfe1|" /opt/mastodon/app/views/layouts/application.html.haml \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-sakura \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light/diff.scss /opt/mastodon/app/javascript/styles/mastodon-sakura/diff.scss \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light/variables.scss /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#9baec8|#b5495b|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#d9e1e8|#fedfe1|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#6364ff|#f596aa|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#858afa|#eb7a77|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#b0c0cf|#feeeed|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && sed -i "s|#9bcbed|#f8c3cd|" /opt/mastodon/app/javascript/styles/mastodon-sakura/variables.scss \
  && cp /opt/mastodon/app/javascript/styles/mastodon-light.scss /opt/mastodon/app/javascript/styles/mastodon-sakura.scss \
  && sed -i "s|light|sakura|" /opt/mastodon/app/javascript/styles/mastodon-sakura.scss \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon (Sakura)' /opt/mastodon/config/locales/en.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-CN.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-TW.yml \
  && sed -i '/mastodon-light/a\    mastodon-sakura: Mastodon · 桜' /opt/mastodon/config/locales/zh-HK.yml \
  && echo -e "mastodon-sakura: styles/mastodon-sakura.scss" >> /opt/mastodon/config/themes.yml \
  && echo "加入 Mastodon Bird UI 主题" \
  && mkdir /opt/mastodon/app/javascript/styles/mastodon-bird-ui \
  && wget -nv https://raw.githubusercontent.com/ronilaukkarinen/mastodon-bird-ui/mastodon-4.1.2-stable/layout-single-column.css -O /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && wget -nv https://raw.githubusercontent.com/ronilaukkarinen/mastodon-bird-ui/mastodon-4.1.2-stable/layout-multiple-columns.css -O /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && sed -i 's/theme-contrast/theme-mastodon-bird-ui-contrast/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && sed -i 's/theme-mastodon-light/theme-mastodon-bird-ui-light/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-single-column.scss \
  && sed -i 's/theme-contrast/theme-mastodon-bird-ui-contrast/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && sed -i 's/theme-mastodon-light/theme-mastodon-bird-ui-light/g' /opt/mastodon/app/javascript/styles/mastodon-bird-ui/layout-multiple-columns.scss \
  && echo -e "@import 'application';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-dark.scss \
  && echo -e "@import 'mastodon-light/variables';\n@import 'application';\n@import 'mastodon-light/diff';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-light.scss \
  && echo -e "@import 'contrast/variables';\n@import 'application';\n@import 'contrast/diff';\n@import 'mastodon-bird-ui/layout-single-column.scss';\n@import 'mastodon-bird-ui/layout-multiple-columns.scss';" > /opt/mastodon/app/javascript/styles/mastodon-bird-ui-contrast.scss \
  && echo -e "mastodon-bird-ui-dark: styles/mastodon-bird-ui-dark.scss\nmastodon-bird-ui-contrast: styles/mastodon-bird-ui-contrast.scss\nmastodon-bird-ui-light: styles/mastodon-bird-ui-light.scss" >> /opt/mastodon/config/themes.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI (Dark)\n    mastodon-bird-ui-contrast: Mastodon Bird UI (High contrast)\n    mastodon-bird-ui-light: Mastodon Bird UI (Light)' /opt/mastodon/config/locales/en.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI（暗色主题）\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高对比度）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色主题）' /opt/mastodon/config/locales/zh-CN.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI（深色）\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高對比）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色）' /opt/mastodon/config/locales/zh-TW.yml \
  && sed -i '/mastodon-light/a\    mastodon-bird-ui-dark: Mastodon Bird UI\n    mastodon-bird-ui-contrast: Mastodon Bird UI（高對比）\n    mastodon-bird-ui-light: Mastodon Bird UI（亮色主題）' /opt/mastodon/config/locales/zh-HK.yml \
  && echo "全文搜索中文优化" \
  && sed -i "s|whitespace|ik_max_word|" /opt/mastodon/app/chewy/accounts_index.rb \
  && sed -i "s|analyzer: {|char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },\n    analyzer: {|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|uax_url_email|ik_max_word|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|        ),|        ),\n        char_filter: %w(tsconvert),|" /opt/mastodon/app/chewy/statuses_index.rb \
  && sed -i "s|analysis: {|analysis: {\n    char_filter: {\n      tsconvert: {\n        type: 'stconvert',\n        keep_both: false,\n        delimiter: '#',\n        convert_type: 't2s',\n      },\n    },|" /opt/mastodon/app/chewy/tags_index.rb \
  && sed -i "s|keyword',|ik_max_word',\n        char_filter: %w(tsconvert),|" /opt/mastodon/app/chewy/tags_index.rb \
  && echo "修改版本项目地址" \
  && sed -i "/def suffix/{n;s|''|'~wxw'|}" /opt/mastodon/lib/mastodon/version.rb \
  && sed -i "s|mastodon/mastodon|wxwmoe/mastodon|" /opt/mastodon/lib/mastodon/version.rb \
  && echo "重新编译资源文件" \
  && OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile \
  && yarn cache clean
