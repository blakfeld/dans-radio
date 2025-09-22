#!/bin/bash

echo "Starting Rails with HTTPS + Port Forwarding..."
echo "========================================="
echo ""

cd /Users/corwinbrown/projects/dans_radio

# Kill any existing servers
pkill -f "puma\|rails server" 2>/dev/null
sudo pfctl -d 2>/dev/null  # Disable any existing forwarding

sleep 1

# Start Rails on port 3001 (no sudo needed)
echo "Starting Rails on port 3001..."
rails server -p 3001 \
  -b 'ssl://0.0.0.0:3001?key=config/certs/dansradio-key.pem&cert=config/certs/dansradio.pem' &
RAILS_PID=$!

sleep 3

# Set up port forwarding from 443 to 3001
echo ""
echo "Setting up port forwarding from 443 to 3001..."
echo "This requires sudo for the port forwarding only"
echo ""

# Create pf rule
echo "rdr pass inet proto tcp from any to any port 443 -> 127.0.0.1 port 3001" | sudo pfctl -ef -

echo ""
echo "========================================="
echo "Server is now available at:"
echo "  https://dansradio.dev/"
echo ""
echo "Spotify Redirect URI:"
echo "  https://dansradio.dev/auth/spotify/callback"
echo ""
echo "Press Ctrl+C to stop"
echo "========================================="

# Wait for Ctrl+C
trap "kill $RAILS_PID; sudo pfctl -d 2>/dev/null; exit" INT
wait
