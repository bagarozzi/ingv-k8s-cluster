#!/bin/bash

# Kubernetes Node Join Script
# This script reads IP addresses from a file and joins worker nodes to a Kubernetes master
# First IP in the file should be the master node, followed by worker nodes

set -e  # Exit on any error

# Configuration
IP_FILE="nodes.txt"
SSH_KEY=".ssh/ingv-key"
SSH_USER="ubuntu"
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to execute SSH command
ssh_exec() {
    local host=$1
    local command=$2
    ssh -i "$SSH_KEY" $SSH_OPTIONS "$SSH_USER@$host" "$command"
}

# Validate inputs
if [[ ! -f "$IP_FILE" ]]; then
    log "ERROR: IP file '$IP_FILE' not found!"
    echo "Please create a file with IP addresses (one per line, master first)"
    exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
    log "ERROR: SSH key file '$SSH_KEY' not found!"
    exit 1
fi

# Check if SSH key has correct permissions
if [[ $(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %A "$SSH_KEY" 2>/dev/null) != "600" ]]; then
    log "WARNING: SSH key permissions should be 600. Attempting to fix..."
    chmod 600 "$SSH_KEY"
fi

# Read IP addresses from file
mapfile -t ips < <(grep -v '^[[:space:]]*$' "$IP_FILE" | grep -v '^#' | tr -d '\r' | sed 's/[[:space:]]*$//')

# Clean and validate IP addresses
cleaned_ips=()
for ip in "${ips[@]}"; do
    # Remove any whitespace and invisible characters
    clean_ip=$(echo "$ip" | tr -d '\r\n\t' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
    if [[ -n "$clean_ip" ]]; then
        cleaned_ips+=("$clean_ip")
    fi
done

# Use cleaned IPs
ips=("${cleaned_ips[@]}")

if [[ ${#ips[@]} -lt 2 ]]; then
    log "ERROR: Need at least 2 IP addresses (1 master + 1 worker)"
    exit 1
fi

MASTER_IP="${ips[0]}"
WORKER_IPS=("${ips[@]:1}")

log "Master node: '$MASTER_IP'"
log "Worker nodes: '${WORKER_IPS[*]}'"

# Test SSH connectivity to all nodes
log "Testing SSH connectivity..."
for ip in "${ips[@]}"; do
    log "Testing connection to $ip..."
    if ssh_exec "$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        log "SSH connection to $ip successful"
    else
        log "ERROR: Cannot SSH to $ip"
        log "Trying with verbose output for debugging..."
        ssh -i "$SSH_KEY" $SSH_OPTIONS "$SSH_USER@$ip" "echo 'SSH connection test'" || true
        exit 1
    fi
done

# Get the kubeadm join command from master
log "Retrieving kubeadm join command from master ($MASTER_IP)..."

# First, try to get existing join command
JOIN_CMD=$(ssh_exec "$MASTER_IP" "sudo kubeadm token create --print-join-command 2>/dev/null" || echo "")

log "Join command retrieved: $JOIN_CMD"

# Join worker nodes
log "Starting to join worker nodes..."

FAILED_JOINS=0

for worker_ip in "${WORKER_IPS[@]}"; do
    log "Joining worker node: $worker_ip"
    
    # Execute join command on worker
    if ssh_exec "$worker_ip" "sudo $JOIN_CMD"; then
        log "Successfully joined worker node: $worker_ip"
        
        # Wait a moment for node to register
        sleep 5
        
    else
        log "Failed to join worker node: $worker_ip"
        ((FAILED_JOINS++))
    fi
    
    echo "----------------------------------------"
done

# Summary
log "Join operation completed!"

if [[ $FAILED_JOINS -gt 0 ]]; then
    log "Some nodes failed to join. Check the logs above for details."
    exit 1
fi

# Display final cluster status
log "Final cluster status:"
ssh_exec "$MASTER_IP" "kubectl get nodes"

log "All worker nodes successfully joined the cluster!"