# frozen_string_literal: true

module Submitters
  module CreateStampAttachment
    WIDTH = 400
    HEIGHT = 200

    TRANSPARENT_PIXEL = "\x89PNG\r\n\u001A\n\u0000\u0000\u0000\rIHDR\u0000" \
                        "\u0000\u0000\u0001\u0000\u0000\u0000\u0001\b\u0004" \
                        "\u0000\u0000\u0000\xB5\u001C\f\u0002\u0000\u0000\u0000" \
                        "\vIDATx\xDAc\xFC_\u000F\u0000\u0002\x83\u0001\x804\xC3ڨ" \
                        "\u0000\u0000\u0000\u0000IEND\xAEB`\x82"

    module_function

    def call(submitter)
      image = generate_stamp_image(submitter)

      image_data = image.write_to_buffer('.png')

      checksum = Digest::MD5.base64digest(image_data)

      attachment = submitter.attachments.joins(:blob).find_by(blob: { checksum: })

      attachment || ActiveStorage::Attachment.create!(
        blob: ActiveStorage::Blob.create_and_upload!(io: StringIO.new(image_data), filename: 'stamp.png'),
        metadata: { analyzed: true, identified: true, width: image.width, height: image.height },
        name: 'attachments',
        record: submitter
      )
    end

    # rubocop:disable Metrics
    def generate_stamp_image(submitter)
      logo = Vips::Image.new_from_buffer(load_logo(submitter).read, '')

      logo = logo.resize([WIDTH / logo.width.to_f, HEIGHT / logo.height.to_f].min)

      base_layer = Vips::Image.black(WIDTH, HEIGHT).new_from_image([255, 255, 255]).copy(interpretation: :srgb)

      opacity_layer = Vips::Image.new_from_buffer(TRANSPARENT_PIXEL, '').resize(WIDTH)

      text = build_text_image(submitter)

      text_layer = text.new_from_image([0, 0, 0]).copy(interpretation: :srgb)
      text_layer = text_layer.bandjoin(text)

      base_layer = base_layer.composite(logo, 'over',
                                        x: (WIDTH - logo.width) / 2,
                                        y: (HEIGHT - logo.height) / 2)

      base_layer = base_layer.composite(opacity_layer, 'over')

      base_layer.composite(text_layer, 'over',
                           x: (WIDTH - text_layer.width) / 2,
                           y: (HEIGHT - text_layer.height) / 2)
    end
    # rubocop:enable Metrics

    def build_text_image(submitter)
      time = I18n.l(submitter.completed_at.in_time_zone(submitter.account.timezone), format: :long,
                                                                                     locale: submitter.account.locale)

      timezone = TimeUtils.timezone_abbr(submitter.account.timezone, submitter.completed_at)

      name = if submitter.name.present? && submitter.email.present?
               "#{submitter.name} #{submitter.email}"
             else
               submitter.name || submitter.email || submitter.phone
             end

      role = if submitter.submission.template_submitters.size > 1
               item = submitter.submission.template_submitters.find { |e| e['uuid'] == submitter.uuid }

               "Role: #{item['name']}\n"
             else
               ''
             end

      text = %(<span size="90">Digitally signed by: <b>#{name}</b>\n#{role}#{time} #{timezone}</span>)

      Vips::Image.text(text, width: WIDTH, height: HEIGHT)
    end

    def load_logo(_submitter)
      PdfIcons.logo_io
    end
  end
end