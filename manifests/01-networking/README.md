# Networking Configuration

This directory contains networking-related Kubernetes resources.

## Traefik Ingress Controller

k3s comes with Traefik pre-installed. This directory is for custom Traefik configurations and additional networking resources.

## Common Resources

- `middleware.yaml` - Traefik middleware (compression, rate limiting, etc.)
- `ingress-class.yaml` - Ingress class definitions
- `tls-options.yaml` - TLS configuration

## Middleware Examples

```yaml
apiVersion: traefik.containo.us/v1alpha1
kind: Middleware
metadata:
  name: compression
  namespace: kube-system
spec:
  compress: {}
```

Usage in Ingress:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: kube-system-compression@kubernetescrd
```

## Ingress Routes

Place your application ingress routes in `99-apps/` directory alongside your deployments.
