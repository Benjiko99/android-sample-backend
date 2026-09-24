# Presence is a stored flag, not a heartbeat: with auth a stub there is no session to
# time out, so Reseed marks the one signed-in sample user online and nobody else.
# add_column is a plain ALTER TABLE ADD on SQLite — no table rebuild, so none of the
# cascade hazard a column removal carries.
class AddOnlineToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :online, :boolean, default: false, null: false

    # Mark u1 online now rather than at the next nightly reseed.
    reversible do |dir|
      dir.up { execute "UPDATE users SET online = TRUE WHERE id = 'u1'" }
    end
  end
end
