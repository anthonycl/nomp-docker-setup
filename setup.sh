#!/bin/bash

# Function to generate random passwords
generate_password() {
  tr -dc A-Za-z0-9_ < /dev/urandom | head -c 32
}

# Function to check and create users
check_and_create_user() {
  local username=$1
  if ! id "$username" &>/dev/null; then
    echo "Creating user: $username"
    useradd -m "$username" || exit 1
  else
    echo "User $username already exists."
  fi
}

# Set variables for Docker images
BITCOIN_IMAGE="bitcoin/bitcoin"
DOGECOIN_IMAGE="casperstack/dogecoin"
NOMP_IMAGE="theretromike/rmt-nomp"

# Create users for Bitcoin and Dogecoin if they don't exist
check_and_create_user "bitcoin"
check_and_create_user "dogecoin"

# Set random passwords for Bitcoin and Dogecoin RPC
BITCOIN_RPCPASSWORD=$(generate_password)
DOGECOIN_RPCPASSWORD=$(generate_password)

echo "Bitcoin RPC password: $BITCOIN_RPCPASSWORD"
echo "Dogecoin RPC password: $DOGECOIN_RPCPASSWORD"

# Install dependencies for compiling blocknotify
echo "Installing required packages..."
apt-get update && apt-get install -y gcc curl make git wget containerd.io

# Download and compile blocknotify C file
echo "Downloading and compiling blocknotify C file..."
curl -sL https://raw.githubusercontent.com/zone117x/node-open-mining-portal/refs/heads/master/scripts/blocknotify.c -o /bin/blocknotify.c

# Inject necessary include for inet_addr into blocknotify.c
echo "Injecting <arpa/inet.h> into blocknotify.c..."
sed -i '1i #include <arpa/inet.h>' /bin/blocknotify.c

# Compile the blocknotify C file
gcc /bin/blocknotify.c -o /bin/blocknotify
chmod +x /bin/blocknotify

# Set up configuration directories for Bitcoin and Dogecoin
echo "Setting up configuration directories for Bitcoin and Dogecoin..."
mkdir -p /root/.bitcoin /root/.dogecoin

# Create bitcoin.conf
echo "Creating bitcoin.conf..."
cat <<EOF > /root/.bitcoin/bitcoin.conf
rpcuser=bitcoinrpc
rpcpassword=$BITCOIN_RPCPASSWORD
rpcallowip=127.0.0.1
EOF

# Create dogecoin.conf
echo "Creating dogecoin.conf..."
cat <<EOF > /root/.dogecoin/dogecoin.conf
rpcuser=dogecoinrpc
rpcpassword=$DOGECOIN_RPCPASSWORD
rpcallowip=127.0.0.1
EOF

# Create Docker Compose file for services
echo "Creating Docker Compose file..."
cat <<EOF > docker-compose.yml
version: '3'

services:
  redis:
    image: redis
    restart: always
    container_name: redis

  bitcoind:
    image: $BITCOIN_IMAGE
    restart: always
    container_name: bitcoind
    environment:
      - BITCOIN_RPCUSER=bitcoinrpc
      - BITCOIN_RPCPASSWORD=$BITCOIN_RPCPASSWORD
      - BITCOIN_RPCALLOWIP=127.0.0.1
    volumes:
      - /root/.bitcoin:/root/.bitcoin
    command: ["bitcoind", "-rpcallowip=127.0.0.1", "-rpcuser=bitcoinrpc", "-rpcpassword=$BITCOIN_RPCPASSWORD"]

  dogecoind:
    image: $DOGECOIN_IMAGE
    restart: always
    container_name: dogecoind
    environment:
      - DOGECOIN_RPCUSER=dogecoinrpc
      - DOGECOIN_RPCPASSWORD=$DOGECOIN_RPCPASSWORD
      - DOGECOIN_RPCALLOWIP=127.0.0.1
    volumes:
      - /root/.dogecoin:/root/.dogecoin
    command: ["dogecoind", "-rpcallowip=127.0.0.1", "-rpcuser=dogecoinrpc", "-rpcpassword=$DOGECOIN_RPCPASSWORD"]

  nomp:
    image: $NOMP_IMAGE
    restart: always
    container_name: nomp
    environment:
      - NOMP_RPCUSER=bitcoinrpc
      - NOMP_RPCPASSWORD=$BITCOIN_RPCPASSWORD
      - NOMP_BTC_RPCURL=http://bitcoinrpc:$BITCOIN_RPCPASSWORD@bitcoind:8332
      - NOMP_DOGE_RPCURL=http://dogecoinrpc:$DOGECOIN_RPCPASSWORD@dogecoind:22555
    volumes:
      - /root/nomp:/root/nomp
    ports:
      - "8080:8080"
    command: ["bash", "-c", "cd /root/nomp && npm install && forever start init.js"]
EOF

# Ensure Docker Compose and Docker are available and running
echo "Building and starting Docker services using built-in Docker Compose..."
docker compose up -d

echo "Setup completed!"
echo "Bitcoin RPC password: $BITCOIN_RPCPASSWORD"
echo "Dogecoin RPC password: $DOGECOIN_RPCPASSWORD"
