class CreateAllTables < ActiveRecord::Migration[8.0]
  def change
    # Create song_requests table
    create_table :song_requests do |t|
      t.string :track_id
      t.string :artist
      t.string :track_title
      t.string :state
      t.string :track_uri

      t.timestamps
    end

    # Create spotify_users table
    create_table :spotify_users do |t|
      t.string :username
      t.string :email
      t.string :token
      t.string :refresh_token
      t.datetime :expires_at
      t.text :spotify_hash

      t.timestamps
    end

    # Create artists table with all fields
    create_table :artists do |t|
      t.string :name
      t.string :spotify_id
      t.text :images
      t.string :uri
      t.string :href

      t.timestamps
    end

    # Create albums table with all fields
    create_table :albums do |t|
      t.string :name
      t.integer :artist_id
      t.string :spotify_id
      t.string :album_type
      t.integer :total_tracks
      t.text :external_urls
      t.string :href
      t.text :images
      t.string :release_date
      t.string :uri

      t.timestamps
    end

    # Create tracks table with all fields
    create_table :tracks do |t|
      t.string :spotify_id
      t.integer :album_id
      t.string :title
      t.integer :duration_ms
      t.boolean :explicit
      t.string :href
      t.boolean :is_playable
      t.string :preview_url
      t.integer :track_number
      t.string :uri

      t.timestamps
    end
  end
end
