# EKS + Karpenter POC

Terraform that brings up an EKS cluster in a fresh VPC with Karpenter handling node autoscaling across both x86 and Graviton (arm64) Spot instances.

## What it builds

- VPC across 3 AZs, public + private subnets, single NAT gateway.
- EKS cluster (configurable version, default `1.33`).
- A 2-node managed node group (`t3.small`, on-demand) tainted `CriticalAddonsOnly`. Hosts Karpenter itself, CoreDNS, and the EKS addons. Nothing else.
- Karpenter v1 installed via the upstream Helm chart, IAM and SQS interruption queue from the official module.
- One `EC2NodeClass` (`default`) and two `NodePool`s (`amd64`, `arm64`), both Spot, with consolidation enabled.

## Prereqs

- AWS account with admin (or close to it) for the apply.
- `terraform` >= 1.6, `aws` CLI v2, `kubectl`, `helm` on PATH.
- AWS credentials exported (`AWS_PROFILE` or env vars).

## Apply

```
terraform init
terraform apply
```

Takes ~15 minutes (EKS control plane is the long pole).

Point kubectl at the cluster:

```
aws eks update-kubeconfig --region us-east-1 --name innovate-poc
```

The exact command is in the `configure_kubectl` output.

## Verify Karpenter is alive

```
kubectl -n kube-system get pods -l app.kubernetes.io/name=karpenter
kubectl get nodepool
kubectl get ec2nodeclass
```

Three pods, two nodepools, one nodeclass.

## Running a pod on x86 or Graviton

A developer picks the architecture with `nodeSelector` on the pod spec:

```yaml
spec:
  nodeSelector:
    kubernetes.io/arch: arm64   # or amd64
```

That's it. Karpenter sees the pending pod, matches the arch requirement against the right NodePool, and provisions a node.

Two ready-to-apply examples:

```
kubectl apply -f manifests/example-arm64.yaml
kubectl apply -f manifests/example-amd64.yaml
```

Watch a node come up:

```
kubectl get nodes -w
```

You should see a new node with `arch=arm64` (or `amd64`) within ~45 seconds.

To check which arch a running pod landed on:

```
kubectl get pod -o wide
kubectl get node <node-name> -o jsonpath='{.metadata.labels.kubernetes\.io/arch}'
```

### Gotcha: image architecture

If the container image is amd64-only and you schedule it on arm64, the pod will CrashLoop with `exec format error`. Build multi-arch images (`docker buildx build --platform linux/amd64,linux/arm64`) or use images that already publish multi-arch manifests (the nginx image used in the examples does).

## Clean up

```
kubectl delete -f manifests/example-amd64.yaml --ignore-not-found
kubectl delete -f manifests/example-arm64.yaml --ignore-not-found
terraform destroy
```

Delete the example deployments first so Karpenter scales the nodes back down before `terraform destroy` tries to remove the cluster.

## Layout

```
.
├── versions.tf         provider/version pins
├── providers.tf        aws, kubernetes, helm, kubectl
├── variables.tf
├── vpc.tf              terraform-aws-modules/vpc
├── eks.tf              terraform-aws-modules/eks + system node group
├── karpenter.tf        karpenter submodule + helm release + NodeClass/NodePools
├── outputs.tf
└── manifests/
    ├── ec2nodeclass.yaml.tftpl   rendered by terraform (needs cluster name + IAM role)
    ├── nodepool-amd64.yaml
    ├── nodepool-arm64.yaml
    ├── example-amd64.yaml        for developers
    └── example-arm64.yaml        for developers
```

Flat on purpose. Reading top to bottom should be enough to understand what gets created.

## Things I'd change for production

- **Per-AZ NAT gateway.** Single NAT is fine for a POC. In prod you want one per AZ to avoid the cross-AZ data charge and the single point of failure.
- **Remote state.** State is local here. Move it to S3 with DynamoDB locking before anyone else applies.
- **Lock down the API endpoint.** Public access is on for the demo. Restrict to a CIDR allowlist (corp VPN, IP allowlist) or go private-only behind a bastion.
- **CloudWatch logs.** Turn on the EKS control plane log types (api, audit, authenticator).
- **An on-demand NodePool.** For workloads that can't tolerate Spot interruption (stateful systems, long-running batch). Add a third NodePool requiring `karpenter.sh/capacity-type: on-demand`.

## Notes

- Karpenter uses Pod Identity for the controller IAM. The cluster still has IRSA enabled for app workloads.
- `karpenter.sh/discovery = <cluster_name>` tags on subnets and the cluster security group let Karpenter find them. The VPC and EKS modules set these.
- Karpenter consolidation runs after a node is empty/underutilized for 1m. Set higher for noisy workloads.
- Instance generation filter is `> 4` to avoid old families that often have worse Spot interruption rates.
