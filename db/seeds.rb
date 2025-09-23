# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create initial admin user if none exists
unless User.admins.exists?
  admin_user = User.create!(
    email: "admin@dansradio.com",
    username: "admin",
    password: "admin123456",  # CHANGE THIS IN PRODUCTION!
    password_confirmation: "admin123456",
    first_name: "Admin",
    last_name: "User",
    admin: true
  )

  puts "Created initial admin user:"
  puts "  Username: admin"
  puts "  Email: admin@dansradio.com"
  puts "  Password: admin123456"
  puts ""
  puts "⚠️  IMPORTANT: Change the admin password immediately after first login!"
end

# Create a regular user for testing (development only)
if Rails.env.development? && !User.exists?(username: "testuser")
  test_user = User.create!(
    email: "user@dansradio.com",
    username: "testuser",
    password: "password123",
    password_confirmation: "password123",
    first_name: "Test",
    last_name: "User",
    admin: false
  )

  puts "Created test user (development only):"
  puts "  Username: testuser"
  puts "  Email: user@dansradio.com"
  puts "  Password: password123"
end
