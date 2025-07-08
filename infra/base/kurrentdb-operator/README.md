# KurrentDB Operator

This directory contains the KurrentDB operator configuration for managing KurrentDB clusters across different environments.

## Overview

KurrentDB is a high-performance event store and message broker designed for event sourcing and streaming applications. The KurrentDB operator simplifies the deployment and management of KurrentDB clusters on Kubernetes.

## Features

- **Automated Deployment**: Deploy KurrentDB clusters with custom resources
- **High Availability**: Support for multi-replica clusters with leader election
- **Monitoring**: Integrated Prometheus metrics and ServiceMonitor
- **Security**: Comprehensive RBAC and security contexts
- **Environment-Specific**: Different configurations for dev, stage, UAT, and production

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    KurrentDB Operator                      │
├─────────────────────────────────────────────────────────────┤
│  • Watches KurrentDB custom resources                      │
│  • Manages StatefulSets, Services, ConfigMaps              │
│  • Handles cluster lifecycle (create, update, delete)      │
│  • Provides health checks and monitoring                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    KurrentDB Clusters                      │
├─────────────────────────────────────────────────────────────┤
│  • High-performance event storage                          │
│  • GRPC and HTTP APIs                                     │
│  • Clustering and replication                             │
│  • Persistent storage with Azure Disks                    │
└─────────────────────────────────────────────────────────────┘
```

## Environment Configuration

### Development
- **Log Level**: Debug
- **Resources**: Minimal (50m CPU, 64Mi RAM)
- **Monitoring**: Enhanced with 15s scrape intervals
- **Reconciliation**: Fast (1s retry period)

### Staging
- **Log Level**: Info
- **Resources**: Moderate (100m CPU, 128Mi RAM)
- **Monitoring**: Standard (30s intervals)
- **Reconciliation**: Standard settings

### UAT
- **Log Level**: Info
- **Resources**: Light (75m CPU, 96Mi RAM)
- **Monitoring**: Standard (30s intervals)
- **Testing**: Optimized for acceptance testing

### Production
- **Log Level**: Warn
- **Resources**: Enhanced (200m CPU, 256Mi RAM)
- **High Availability**: 2 replicas with anti-affinity
- **Security**: Network policies enabled
- **Monitoring**: Conservative (60s intervals)

## Custom Resources

Once the operator is deployed, you can create KurrentDB clusters using custom resources:

```yaml
apiVersion: kurrent.io/v1alpha1
kind: KurrentDB
metadata:
  name: my-eventstore
  namespace: default
spec:
  replicas: 3
  version: "latest"
  storage:
    size: 100Gi
    storageClass: managed-premium
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  configuration:
    clusterSize: 3
    nodePort: 2113
    httpPort: 2114
```

## Monitoring

The operator provides comprehensive monitoring:

### Operator Metrics
- Controller manager metrics on port 8080
- Health checks on port 8081
- Webhook metrics on port 9443

### KurrentDB Metrics
- Cluster health and performance metrics
- Event store statistics
- Replication lag monitoring
- Resource utilization

### ServiceMonitor Configuration
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kurrentdb-operator
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kurrentdb-operator
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

## Security

### RBAC
The operator requires specific permissions to manage KurrentDB resources:
- Create/update/delete StatefulSets, Services, ConfigMaps
- Watch and list KurrentDB custom resources
- Create events for logging and debugging

### Security Context
- Runs as non-root user (65532)
- Read-only root filesystem
- No privilege escalation
- Drops all capabilities

### Network Policies
Production environments enable network policies to restrict traffic:
- Operator can communicate with Kubernetes API
- KurrentDB clusters can communicate with each other
- External access controlled via ingress

## Storage

KurrentDB requires persistent storage for event data:

### Azure Storage Classes
- **Development**: `default` (Standard HDD)
- **Staging/UAT**: `managed` (Standard SSD)
- **Production**: `managed-premium` (Premium SSD)

### Storage Configuration
```yaml
spec:
  storage:
    size: 100Gi
    storageClass: managed-premium
    accessModes:
      - ReadWriteOnce
```

## Networking

### Service Types
- **ClusterIP**: Internal cluster communication
- **LoadBalancer**: External access (production)
- **NodePort**: Development and testing

### Ports
- **2113**: Native TCP protocol
- **2114**: HTTP API
- **8080**: Metrics (operator)
- **9443**: Webhook (operator)

## Backup and Recovery

### Backup Strategy
1. **Volume Snapshots**: Azure Disk snapshots
2. **Configuration Backup**: Export custom resources
3. **Event Data Export**: Use KurrentDB tools

### Recovery Process
1. Restore volume from snapshot
2. Apply custom resource configurations
3. Verify cluster health and data integrity

## Troubleshooting

### Common Issues

1. **Operator Not Starting**
   ```bash
   kubectl logs -n kurrentdb-system deployment/kurrentdb-operator
   kubectl describe pod -n kurrentdb-system -l app.kubernetes.io/name=kurrentdb-operator
   ```

2. **Custom Resource Not Reconciled**
   ```bash
   kubectl describe kurrentdb my-eventstore
   kubectl get events --field-selector involvedObject.name=my-eventstore
   ```

3. **Storage Issues**
   ```bash
   kubectl get pvc
   kubectl describe pv
   kubectl get storageclass
   ```

### Debug Commands
```bash
# Check operator status
kubectl get pods -n kurrentdb-system
kubectl logs -n kurrentdb-system deployment/kurrentdb-operator

# Check custom resources
kubectl get kurrentdb -A
kubectl describe kurrentdb <name>

# Check operator metrics
kubectl port-forward -n kurrentdb-system svc/kurrentdb-operator-metrics 8080:8080
curl http://localhost:8080/metrics
```

## Upgrade Path

### Operator Upgrades
Renovate will automatically create PRs for operator updates:
- **Patch versions**: Auto-merged
- **Minor versions**: Manual approval
- **Major versions**: Manual approval with testing

### KurrentDB Upgrades
Update the version in your custom resource:
```yaml
spec:
  version: "v2.1.0"
```

## Best Practices

1. **Resource Limits**: Always set appropriate resource requests/limits
2. **Storage Planning**: Plan for growth with appropriate storage sizes
3. **Monitoring**: Enable monitoring in all environments
4. **Backup Strategy**: Implement regular backup procedures
5. **Security**: Use network policies and RBAC in production
6. **Testing**: Validate upgrades in non-production environments first

## Integration with Flux

The operator is fully integrated with your Flux GitOps setup:
- **Automated Deployment**: Deployed via Helm through Flux
- **Environment Separation**: Different configs per environment
- **Monitoring Integration**: ServiceMonitors deployed automatically
- **Update Management**: Renovate handles dependency updates

---

For more information about KurrentDB, visit: https://kurrent.io
