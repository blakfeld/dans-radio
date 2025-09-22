class CreateRequestQueues < ActiveRecord::Migration[8.0]
  def change
    create_table :request_queues do |t|
      t.references :spotify_user, null: false, foreign_key: true
      t.string :playlist_id
      t.string :playlist_name
      t.references :current_track, foreign_key: { to_table: :tracks }
      t.references :next_track, foreign_key: { to_table: :tracks }
      t.integer :position, default: 0
      t.boolean :active, default: false
      t.datetime :last_sync_at
      t.string :sync_status # synced, out_of_sync, recovering

      t.timestamps
    end

    add_index :request_queues, :active
    add_index :request_queues, :playlist_id
  end
end
