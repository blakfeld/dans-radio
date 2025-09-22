class AddRequestQueueToSongRequests < ActiveRecord::Migration[8.0]
  def change
    add_reference :song_requests, :request_queue, foreign_key: true
    add_column :song_requests, :position, :integer
    add_column :song_requests, :queued_at, :datetime
    add_column :song_requests, :played_at, :datetime
    add_column :song_requests, :status, :string, default: 'pending'

    add_index :song_requests, :status
    add_index :song_requests, [ :request_queue_id, :position ]
  end
end
