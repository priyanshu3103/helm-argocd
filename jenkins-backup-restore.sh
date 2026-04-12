#!/bin/bash
# jenkins-backup-restore.sh

NAMESPACE="devops-tools"
BACKUP_FILE="jenkins-backup.tar.gz"

# Function to show usage
usage() {
    echo "Usage: $0 {backup|restore [backup-file]}"
    echo "  backup              - Backup Jenkins home directory"
    echo "  restore [file]      - Restore Jenkins home from backup file (default: jenkins-backup.tar.gz)"
    exit 1
}

# Function to get Jenkins pod name
get_jenkins_pod() {
    kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[0].metadata.name}'
}

# Function to backup
backup() {
    local POD_NAME=$(get_jenkins_pod)
    
    if [ -z "$POD_NAME" ]; then
        echo "❌ No Jenkins pod found in namespace: $NAMESPACE"
        exit 1
    fi
    
    echo "✅ Found Jenkins pod: $POD_NAME"
    
    # Create backup
    echo "📦 Creating backup of Jenkins home..."
    kubectl exec -n $NAMESPACE $POD_NAME -- tar czf /tmp/jenkins-backup.tar.gz /var/jenkins_home 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "❌ Backup creation failed!"
        exit 1
    fi
    
    # Copy to local
    echo "📥 Copying backup to local machine..."
    kubectl cp $NAMESPACE/$POD_NAME:/tmp/jenkins-backup.tar.gz ./$BACKUP_FILE
    
    if [ $? -ne 0 ]; then
        echo "❌ Failed to copy backup file!"
        exit 1
    fi
    
    # Check backup size
    BACKUP_SIZE=$(ls -lh $BACKUP_FILE | awk '{print $5}')
    echo "✅ Backup created successfully! Size: $BACKUP_SIZE"
    
    # Cleanup temp file in pod
    kubectl exec -n $NAMESPACE $POD_NAME -- rm -f /tmp/jenkins-backup.tar.gz
    
    # List backup contents preview
    echo "📋 Backup contents preview:"
    tar tzf $BACKUP_FILE | head -10
    echo "..."
}

# Function to restore
restore() {
    local RESTORE_FILE=${1:-$BACKUP_FILE}
    local POD_NAME=$(get_jenkins_pod)
    
    # Check if restore file exists
    if [ ! -f "$RESTORE_FILE" ]; then
        echo "❌ Backup file not found: $RESTORE_FILE"
        exit 1
    fi
    
    if [ -z "$POD_NAME" ]; then
        echo "❌ No Jenkins pod found in namespace: $NAMESPACE"
        exit 1
    fi
    
    echo "✅ Found Jenkins pod: $POD_NAME"
    echo "📦 Restore file: $RESTORE_FILE"
    
    # Scale down deployment to avoid conflicts
    echo "🛑 Scaling down Jenkins deployment..."
    kubectl scale deployment -n $NAMESPACE jenkins --replicas=0
    
    # Wait for pod to terminate
    echo "⏳ Waiting for Jenkins pod to terminate..."
    sleep 10
    
    # Copy backup to pod (using a temporary pod with PVC access)
    echo "📤 Copying backup to PVC..."
    
    # Get PVC name
    PVC_NAME=$(kubectl get pvc -n $NAMESPACE -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$PVC_NAME" ]; then
        PVC_NAME="jenkins-jenkins-pvc"
    fi
    echo "✅ Using PVC: $PVC_NAME"
    
    # Create temporary pod to restore data
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jenkins-restore-temp
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  volumes:
    - name: jenkins-data
      persistentVolumeClaim:
        claimName: $PVC_NAME
  containers:
    - name: restore
      image: alpine:latest
      command: ["sleep", "3600"]
      volumeMounts:
        - name: jenkins-data
          mountPath: /data
EOF
    
    # Wait for temp pod to be ready
    echo "⏳ Waiting for restore pod to be ready..."
    kubectl wait --for=condition=ready pod/jenkins-restore-temp -n $NAMESPACE --timeout=60s
    
    # Copy backup file to temp pod
    echo "📤 Copying backup to restore pod..."
    kubectl cp $RESTORE_FILE $NAMESPACE/jenkins-restore-temp:/tmp/backup.tar.gz
    
    # Extract backup to data volume
    echo "📂 Extracting backup to PVC..."
    kubectl exec -n $NAMESPACE jenkins-restore-temp -- tar xzf /tmp/backup.tar.gz -C /data --strip-components=1
    
    if [ $? -ne 0 ]; then
        echo "❌ Restore extraction failed!"
        kubectl delete pod jenkins-restore-temp -n $NAMESPACE
        exit 1
    fi
    
    # Clean up temp pod
    echo "🧹 Cleaning up restore pod..."
    kubectl delete pod jenkins-restore-temp -n $NAMESPACE
    
    # Scale up deployment
    echo "🔄 Scaling up Jenkins deployment..."
    kubectl scale deployment -n $NAMESPACE jenkins --replicas=1
    
    # Wait for Jenkins to be ready
    echo "⏳ Waiting for Jenkins to be ready..."
    kubectl rollout status deployment -n $NAMESPACE jenkins --timeout=300s
    
    echo "✅ Restore completed successfully!"
}

# Main logic
case "$1" in
    backup)
        backup
        ;;
    restore)
        restore "$2"
        ;;
    *)
        usage
        ;;
esac