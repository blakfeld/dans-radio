class AddBioToArtists < ActiveRecord::Migration[8.0]
  def change
    add_column :artists, :bio, :text
    add_column :artists, :genres, :text  # Serialized array of genres
    add_column :artists, :popularity, :integer
  end
end
