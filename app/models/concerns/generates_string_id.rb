# Assigns an opaque, collision-resistant string primary key on create when one
# was not supplied. Seed data provides fixed ids (e.g. "p1"); runtime-created
# rows (comments) get a generated id. Clients treat ids as opaque strings.
module GeneratesStringId
  extend ActiveSupport::Concern

  included do
    # Per-model id prefix (e.g. "p" for posts) — keeps ids readable per type.
    # Seed rows supply fixed ids; runtime-created rows get "<prefix><random>".
    class_attribute :id_prefix, instance_writer: false, default: "c"
    before_create :assign_string_id
  end

  private

  def assign_string_id
    self.id = "#{self.class.id_prefix}#{SecureRandom.alphanumeric(24).downcase}" if id.blank?
  end
end
