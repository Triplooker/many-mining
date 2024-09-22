#!/bin/bash

curl -s https://raw.githubusercontent.com/zunxbt/logo/main/logo.sh | bash

sleep 3

ARCH=$(uname -m)

show() {
    echo -e "\033[1;35m$1\033[0m"
}

if ! command -v jq &> /dev/null; then
    show "jq not found, installing..."
    sudo apt-get update
    sudo apt-get install -y jq > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        show "Failed to install jq. Please check your package manager."
        exit 1
    fi
fi

check_latest_version() {
    for i in {1..3}; do
        LATEST_VERSION=$(curl -s https://api.github.com/repos/hemilabs/heminetwork/releases/latest | jq -r '.tag_name')
        if [ -n "$LATEST_VERSION" ]; then
            show "Latest version available: $LATEST_VERSION"
            return 0
        fi
        show "Attempt $i: Failed to fetch the latest version. Retrying..."
        sleep 2
    done

    show "Failed to fetch the latest version after 3 attempts. Please check your internet connection or GitHub API limits."
    exit 1
}

check_latest_version

download_required=true

if [ "$ARCH" == "x86_64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_amd64" ]; then
        show "Latest version for x86_64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
elif [ "$ARCH" == "arm64" ]; then
    if [ -d "heminetwork_${LATEST_VERSION}_linux_arm64" ]; then
        show "Latest version for arm64 is already downloaded. Skipping download."
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
        download_required=false
    fi
fi

if [ "$download_required" = true ]; then
    if [ "$ARCH" == "x86_64" ]; then
        show "Downloading for x86_64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_amd64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_amd64" || { show "Failed to change directory."; exit 1; }
    elif [ "$ARCH" == "arm64" ]; then
        show "Downloading for arm64 architecture..."
        wget --quiet --show-progress "https://github.com/hemilabs/heminetwork/releases/download/$LATEST_VERSION/heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" -O "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz"
        tar -xzf "heminetwork_${LATEST_VERSION}_linux_arm64.tar.gz" > /dev/null
        cd "heminetwork_${LATEST_VERSION}_linux_arm64" || { show "Failed to change directory."; exit 1; }
    else
        show "Unsupported architecture: $ARCH"
        exit 1
    fi
else
    show "Skipping download as the latest version is already present."
fi

read -p "Enter the number of wallets you want to create: " wallet_count

for ((i=1; i<=wallet_count; i++)); do
    echo ""
    show "Select option for wallet $i:"
    show "1. Use new wallet for PoP mining"
    show "2. Use existing wallet for PoP mining"
    
    read -p "Enter your choice (1/2): " choice
    
    if [ "$choice" == "1" ]; then
        show "Generating a new wallet..."
        ./keygen -secp256k1 -json -net="testnet" > ~/popm-address-$i.json
        
        if [ $? -ne 0 ]; then
            show "Failed to generate wallet."
            exit 1
        fi
        
        cat ~/popm-address-$i.json
        
        read -p "Have you saved the above details? (y/N): " saved
        
        if [[ "$saved" =~ ^[Yy]$ ]]; then
            priv_key=$(jq -r '.private_key' ~/popm-address-$i.json)
            read -p "Enter static fee (numerical only, recommended: 100-200): " static_fee
            
            # Создание systemd сервиса для нового кошелька 
            cat << EOF | sudo tee /etc/systemd/system/hemi$i.service > /dev/null
[Unit]
Description=Hemi Network popmd Service for Wallet $i
After=network.target

[Service]
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/popmd
Environment="POPM_BTC_PRIVKEY=$priv_key"
Environment="POPM_STATIC_FEE=$static_fee"
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
            
            sudo systemctl daemon-reload
            sudo systemctl enable hemi$i.service
            sudo systemctl start hemi$i.service
            
            show "PoP mining started for wallet $i"
            
        else 
            echo "Please save the wallet details before proceeding."
            exit 1 
        fi
        
    elif [ "$choice" == "2" ]; then 
        read -p "Enter your Private key: " priv_key 
        read -p "Enter static fee (numerical only, recommended: 100-200): " static_fee
        
        # Создание systemd сервиса для существующего кошелька 
        cat << EOF | sudo tee /etc/systemd/system/hemi$i.service > /dev/null 
[Unit] 
Description=Hemi Network popmd Service for Wallet $i 
After=network.target 

[Service] 
WorkingDirectory=$(pwd) 
ExecStart=$(pwd)/popmd 
Environment="POPM_BTC_PRIVKEY=$priv_key" 
Environment="POPM_STATIC_FEE=$static_fee" 
Environment="POPM_BFG_URL=wss://testnet.rpc.hemi.network/v1/ws/public" 
Restart=on-failure 

[Install] 
WantedBy=multi-user.target 
EOF
        
        sudo systemctl daemon-reload 
        sudo systemctl enable hemi$i.service 
        sudo systemctl start hemi$i.service 
        
        show "PoP mining started for existing wallet $i" 
        
    else 
        echo "Invalid choice. Please select either 1 or 2." 
        exit 1 
    fi 
done

echo ""
show "All wallets have been set up and mining has started."