# Puma configuration for SSL in development
# Use this with: rails s -C config/puma_ssl.rb

require_relative "./puma"

cert_path = Rails.root.join("config", "certs")
FileUtils.mkdir_p(cert_path)

# Use mkcert certificates if they exist, otherwise generate self-signed
mkcert_key = cert_path.join("localhost-key.pem")
mkcert_cert = cert_path.join("localhost.pem")

if File.exist?(mkcert_key) && File.exist?(mkcert_cert)
  key_file = mkcert_key
  cert_file = mkcert_cert
  puts "Using mkcert certificates"
else
  key_file = cert_path.join("localhost.key")
  cert_file = cert_path.join("localhost.crt")

  unless File.exist?(key_file) && File.exist?(cert_file)
    puts "Generating self-signed SSL certificate..."
    system("openssl req -new -newkey rsa:2048 -sha256 -days 365 -nodes -x509 -keyout #{key_file} -out #{cert_file} -subj '/CN=localhost'")
  end
  puts "Using self-signed certificate (browser will show warning)"
end

# Configure SSL
ssl_bind "0.0.0.0", 3001, {
  key: key_file.to_s,
  cert: cert_file.to_s
}

puts "=" * 60
puts "Server will be available at:"
puts "  HTTPS: https://localhost:3001"
puts "  HTTP:  http://localhost:3000"
puts "=" * 60
