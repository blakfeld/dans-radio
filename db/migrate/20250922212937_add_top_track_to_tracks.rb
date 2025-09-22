class AddTopTrackToTracks < ActiveRecord::Migration[8.0]
  def change
    add_column :tracks, :is_top_track, :boolean, default: false
    add_column :tracks, :popularity, :integer

    # Add index for faster querying of top tracks
    add_index :tracks, [ :album_id, :is_top_track ]
    add_index :tracks, :popularity
  end
end
