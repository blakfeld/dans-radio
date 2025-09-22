class UpdateRequestQueueToSingleton < ActiveRecord::Migration[8.0]
  def change
    # Remove the foreign key and column for spotify_user_id
    remove_foreign_key :request_queues, :spotify_users if foreign_key_exists?(:request_queues, :spotify_users)
    remove_column :request_queues, :spotify_user_id, :integer

    # Remove the active index since we'll only have one queue
    remove_index :request_queues, :active if index_exists?(:request_queues, :active)

    # Ensure we only have one queue record
    reversible do |dir|
      dir.up do
        # Keep only the first queue if multiple exist
        if RequestQueue.count > 1
          first_queue = RequestQueue.first
          RequestQueue.where.not(id: first_queue.id).destroy_all
        end

        # Add a unique constraint to ensure only one row can exist
        # We'll use a check constraint or unique index on a constant column
        add_column :request_queues, :singleton_guard, :integer, default: 0, null: false
        add_index :request_queues, :singleton_guard, unique: true
      end

      dir.down do
        remove_index :request_queues, :singleton_guard if index_exists?(:request_queues, :singleton_guard)
        remove_column :request_queues, :singleton_guard, :integer

        # Re-add the removed columns/indexes
        add_column :request_queues, :spotify_user_id, :integer
        add_index :request_queues, :active
      end
    end
  end
end
