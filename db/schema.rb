# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_23_005034) do
  create_table "albums", force: :cascade do |t|
    t.string "name"
    t.integer "artist_id"
    t.string "spotify_id"
    t.string "album_type"
    t.integer "total_tracks"
    t.text "external_urls"
    t.string "href"
    t.text "images"
    t.string "release_date"
    t.string "uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "available_markets"
    t.string "label"
    t.integer "popularity"
    t.index ["popularity"], name: "index_albums_on_popularity"
  end

  create_table "artists", force: :cascade do |t|
    t.string "name"
    t.string "spotify_id"
    t.text "images"
    t.string "uri"
    t.string "href"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "bio"
    t.text "genres"
    t.integer "popularity"
    t.text "external_urls"
    t.integer "followers"
    t.index ["followers"], name: "index_artists_on_followers"
  end

  create_table "request_queues", force: :cascade do |t|
    t.string "playlist_id"
    t.string "playlist_name"
    t.integer "current_track_id"
    t.integer "next_track_id"
    t.integer "position", default: 0
    t.boolean "active", default: false
    t.datetime "last_sync_at"
    t.string "sync_status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "singleton_guard", default: 0, null: false
    t.index ["current_track_id"], name: "index_request_queues_on_current_track_id"
    t.index ["next_track_id"], name: "index_request_queues_on_next_track_id"
    t.index ["playlist_id"], name: "index_request_queues_on_playlist_id"
    t.index ["singleton_guard"], name: "index_request_queues_on_singleton_guard", unique: true
  end

  create_table "song_requests", force: :cascade do |t|
    t.string "track_id"
    t.string "artist"
    t.string "track_title"
    t.string "state"
    t.string "track_uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "request_queue_id"
    t.integer "position"
    t.datetime "queued_at"
    t.datetime "played_at"
    t.string "status", default: "pending"
    t.index ["request_queue_id", "position"], name: "index_song_requests_on_request_queue_id_and_position"
    t.index ["request_queue_id"], name: "index_song_requests_on_request_queue_id"
    t.index ["status"], name: "index_song_requests_on_status"
  end

  create_table "spotify_users", force: :cascade do |t|
    t.string "username"
    t.string "email"
    t.string "token"
    t.string "refresh_token"
    t.datetime "expires_at"
    t.text "spotify_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "tracks", force: :cascade do |t|
    t.string "spotify_id"
    t.integer "album_id"
    t.string "title"
    t.integer "duration_ms"
    t.boolean "explicit"
    t.string "href"
    t.boolean "is_playable"
    t.string "preview_url"
    t.integer "track_number"
    t.string "uri"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "is_top_track", default: false
    t.integer "popularity"
    t.index ["album_id", "is_top_track"], name: "index_tracks_on_album_id_and_is_top_track"
    t.index ["popularity"], name: "index_tracks_on_popularity"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "username", null: false
    t.string "password_digest", null: false
    t.string "first_name"
    t.string "last_name"
    t.boolean "admin", default: false, null: false
    t.string "remember_token"
    t.datetime "remember_token_expires_at"
    t.datetime "last_login_at"
    t.integer "failed_login_attempts", default: 0
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["remember_token"], name: "index_users_on_remember_token"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "request_queues", "tracks", column: "current_track_id"
  add_foreign_key "request_queues", "tracks", column: "next_track_id"
  add_foreign_key "song_requests", "request_queues"
end
