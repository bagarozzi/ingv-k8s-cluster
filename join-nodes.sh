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

# Debug: Show IP lengths to detect hidden characters
log "Debug - Master IP length: ${#MASTER_IP}"
for i in "${!WORKER_IPS[@]}"; do
    log "Debug - Worker IP[$i] length: ${#WORKER_IPS[$i]}"
done

# Test SSH connectivity to all nodes
log "Testing SSH connectivity..."
for ip in "${ips[@]}"; do
    log "Testing connection to $ip..."
    if ssh_exec "$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        log "✓ SSH connection to $ip successful"
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

if [[ -z "$JOIN_CMD" ]]; then
    log "ERROR: Failed to get kubeadm join command from master"
    log "Please ensure:"
    log "1. Kubernetes is properly initialized on the master"
    log "2. The master node is accessible via SSH"
    log "3. The user has sudo privileges"
    exit 1
fi

log "Join command retrieved: $JOIN_CMD"

# Verify master node is ready
log "Verifying master node status..."
MASTER_STATUS=$(ssh_exec "$MASTER_IP" "kubectl get nodes --no-headers | grep master | awk '{print \$2}'" || echo "Unknown")
log "Master node status: $MASTER_STATUS"

# Join worker nodes
log "Starting to join worker nodes..."

SUCCESSFUL_JOINS=0
FAILED_JOINS=0

for worker_ip in "${WORKER_IPS[@]}"; do
    log "Joining worker node: $worker_ip"
    
    # Check if node is already part of the cluster
    EXISTING_NODE=$(ssh_exec "$MASTER_IP" "kubectl get nodes --no-headers | grep '$worker_ip' || echo 'NOT_FOUND'")
    
    if [[ "$EXISTING_NODE" != "NOT_FOUND" ]]; then
        log "WARNING: Node $worker_ip appears to already be in the cluster"
        log "Node info: $EXISTING_NODE"
        read -p "Do you want to reset and rejoin this node? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Resetting node $worker_ip..."
            ssh_exec "$worker_ip" "sudo kubeadm reset -f" || log "WARNING: Reset failed, continuing anyway"
        else
            log "Skipping node $worker_ip"
            continue
        fi
    fi
    
    # Execute join command on worker
    if ssh_exec "$worker_ip" "sudo $JOIN_CMD"; then
        log "✓ Successfully joined worker node: $worker_ip"
        ((SUCCESSFUL_JOINS++))
        
        # Wait a moment for node to register
        sleep 5
        
        # Verify the node joined successfully
        NODE_STATUS=$(ssh_exec "$MASTER_IP" "kubectl get nodes --no-headers | grep '$worker_ip' | awk '{print \$2}'" || echo "Unknown")
        log "Node $worker_ip status: $NODE_STATUS"
        
    else
        log "✗ Failed to join worker node: $worker_ip"
        ((FAILED_JOINS++))
    fi
    
    echo "----------------------------------------"
done

# Summary
log "Join operation completed!"
log "Successful joins: $SUCCESSFUL_JOINS"
log "Failed joins: $FAILED_JOINS"

if [[ $FAILED_JOINS -gt 0 ]]; then
    log "Some nodes failed to join. Check the logs above for details."
    exit 1
fi

# Display final cluster status
log "Final cluster status:"
ssh_exec "$MASTER_IP" "sudo kubectl get nodes"

log "All worker nodes successfully joined the cluster!"