# Port-Forwarding Setup for Local Development

After deployment, set up port-forwarding to access `http://shelfware.local:8080` locally.

## Automatic Setup (One Command)

```bash
# Terminal 1 - Start port-forward (keeps running)
export KUBECONFIG=./INFRA/terraform/kubeconfigs/merged-admin.yaml
kubectl port-forward svc/ingress-nginx-controller -n ingress-nginx 8080:80 \
  --context shelfware-app-admin
```

**Output:**
```
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

Once this is running, **http://shelfware.local:8080** is immediately accessible!

## DNS Resolution

Make sure `/etc/hosts` contains:
```
127.0.0.1  shelfware.local
127.0.0.1  test.shelfware.local
```

## Quick Access

In another terminal:
```bash
# Test it's working
curl http://shelfware.local:8080/

# Or open in browser
open http://shelfware.local:8080
```

## Why Port-Forwarding?

✅ No LoadBalancer costs (~$16-20/month savings)
✅ Works for local/development
✅ Full access to all services (backend, frontend, monitoring)
✅ Can re-enable LoadBalancer later by uncommenting [INFRA/ingress-nginx/install.yaml](INFRA/ingress-nginx/install.yaml)

## To Re-Enable LoadBalancer for Production

Edit [INFRA/ingress-nginx/install.yaml](INFRA/ingress-nginx/install.yaml), uncomment the LoadBalancer service definition and change back to `type: LoadBalancer`.
