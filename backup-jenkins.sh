#!/bin/bash
# backup-jenkins.sh

NAMESPACE="devops-tools"

# Get the running Jenkins pod name
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=jenkins -o jsonpath='{.items[0].metadata.name}')

if [ -z "$POD_NAME" ]; then
    echo "No Jenkins pod found!"
    exit 1
fi

echo "Found Jenkins pod: $POD_NAME"

# Create backup
echo "Creating backup of Jenkins home..."
kubectl exec -n $NAMESPACE $POD_NAME -- tar czf /tmp/jenkins-backup.tar.gz /var/jenkins_home 2>/dev/null

# Copy to local
echo "Copying backup to local machine..."
kubectl cp $NAMESPACE/$POD_NAME:/tmp/jenkins-backup.tar.gz ./jenkins-backup.tar.gz

# Check backup size
BACKUP_SIZE=$(ls -lh jenkins-backup.tar.gz | awk '{print $5}')
echo "Backup created successfully! Size: $BACKUP_SIZE"

# Optional: List backup contents
echo "Backup contents preview:"
tar tzf jenkins-backup.tar.gz | head -10