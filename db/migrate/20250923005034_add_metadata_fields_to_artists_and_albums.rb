class AddMetadataFieldsToArtistsAndAlbums < ActiveRecord::Migration[8.0]
  def change
    # Add metadata fields to artists table
    add_column :artists, :external_urls, :text unless column_exists?(:artists, :external_urls)
    add_column :artists, :followers, :integer unless column_exists?(:artists, :followers)

    # Add metadata fields to albums table
    add_column :albums, :available_markets, :text unless column_exists?(:albums, :available_markets)
    add_column :albums, :label, :string unless column_exists?(:albums, :label)
    add_column :albums, :popularity, :integer unless column_exists?(:albums, :popularity)

    # Add indexes for performance
    add_index :artists, :followers unless index_exists?(:artists, :followers)
    add_index :albums, :popularity unless index_exists?(:albums, :popularity)
  end
end
