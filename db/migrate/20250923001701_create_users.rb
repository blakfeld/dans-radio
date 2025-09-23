class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :username, null: false
      t.string :password_digest, null: false
      t.string :first_name
      t.string :last_name
      t.boolean :admin, default: false, null: false
      t.string :remember_token
      t.datetime :remember_token_expires_at
      t.datetime :last_login_at
      t.integer :failed_login_attempts, default: 0
      t.datetime :locked_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :username, unique: true
    add_index :users, :remember_token
  end
end
