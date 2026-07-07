class RemoveAvatarUrlFromUsers < ActiveRecord::Migration[8.0]
  def change
    # The avatar is now an Active Storage attachment (see User#avatar), not a
    # client-supplied URL string.
    remove_column :users, :avatar_url, :string
  end
end
