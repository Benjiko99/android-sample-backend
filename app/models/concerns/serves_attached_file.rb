# For records that are *either* seed data pointing at an external url *or* a
# client upload held in Active Storage. The generated url method hides which, so
# serializers never have to ask.
#
# Proxying (rather than redirecting) streams the bytes through the app in one
# hop, which is what the Android client's Coil expects. That decision lives here
# alone — changing it should not mean remembering every model that uploads.
module ServesAttachedFile
  extend ActiveSupport::Concern

  class_methods do
    # Declares the attachment and a matching url method in one line. By default a
    # `file` attachment falls back to the `url` column and reads through
    # #display_url; a record with more than one such attachment (a video's `file`
    # and `thumbnail`) names its own fallback column and reader:
    #
    #   serves_attached :file
    #   serves_attached :thumbnail, fallback: :thumbnail_url, as: :thumbnail_display_url
    def serves_attached(name, fallback: :url, as: :display_url)
      has_one_attached name

      define_method(as) do
        attachment = public_send(name)
        return self[fallback] unless attachment.attached?

        Rails.application.routes.url_helpers.rails_storage_proxy_url(attachment)
      end
    end
  end
end
