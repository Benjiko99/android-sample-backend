# For records that are *either* seed data pointing at an external `url` *or* a
# client upload held in Active Storage. `display_url` hides which, so serializers
# never have to ask.
#
# Proxying (rather than redirecting) streams the bytes through the app in one
# hop, which is what the Android client's Coil expects. That decision lives here
# alone — changing it should not mean remembering every model that uploads.
module ServesAttachedFile
  extend ActiveSupport::Concern

  class_methods do
    # Declares the attachment and the matching #display_url in one line.
    def serves_attached(name)
      has_one_attached name

      define_method(:display_url) do
        attachment = public_send(name)
        return self[:url] unless attachment.attached?

        Rails.application.routes.url_helpers.rails_storage_proxy_url(attachment)
      end
    end
  end
end
