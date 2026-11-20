# Terraform AWS VPC

A variable-driven Terraform template for an AWS VPC with configurable public and
private subnets. Each subnet gets its own route table. Public subnets get
internet-gateway routes; Regional NAT mode also creates an internet gateway
when no public subnets are configured.

## Requirements

- Terraform 1.10 or later
- AWS credentials configured for the account where you want to create resources
- Availability zones valid for the selected AWS region

## Configure

Copy `terraform.tfvars.example` to `terraform.tfvars` and edit the values:

```hcl
aws_region = "us-east-1"
vpc_name   = "example-vpc"
vpc_cidr   = "10.0.0.0/16"

public_subnets = {
  public-a = {
    cidr_block        = "10.0.1.0/24"
    availability_zone = "us-east-1a"
  }
}

private_subnets = {
  private-a = {
    cidr_block        = "10.0.11.0/24"
    availability_zone = "us-east-1a"
  }
  private-b = {
    cidr_block        = "10.0.12.0/24"
    availability_zone = "us-east-1b"
  }
}

nat_gateway_mode     = "None"
zonal_nat_gateway_availability_zones = null
enable_dns_support   = true
enable_dns_hostnames = true

tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
}
```

### Variable reference

- `aws_region`: AWS region where the VPC and its resources are created. Every
  subnet's `availability_zone` must be valid in this region.
- `vpc_name`: VPC name, also used for the `Project` tag.
- `vpc_cidr`: IPv4 address range for the VPC. Every subnet range must fit
  inside it, and subnet ranges must not overlap.
- `public_subnets`: Map of public subnet definitions. Each entry has a
  `cidr_block` and `availability_zone`; its map key becomes the subnet's `Name`
  tag. Public subnets assign public IPv4 addresses on launch and have a default
  route to the internet gateway. Set to `{}` for none.
- `private_subnets`: Map of private subnet definitions with the same fields
  and key behavior. Private subnets do not assign public IPs and have no
  internet default route unless NAT is enabled. Set to `{}` for none.
- `nat_gateway_mode`: Controls outbound internet access from private subnets:
  - `None` (default): creates no NAT gateway and adds no internet route to
    private subnet route tables.
  - `Zonal`: creates NAT gateways and private-subnet internet routes in the AZs
    selected by `zonal_nat_gateway_availability_zones`. NAT gateways incur
    hourly and data-processing charges.
  - `Regional`: creates one native AWS Regional NAT Gateway for private
    subnets. It requires internet-gateway connectivity and incurs charges.
- `zonal_nat_gateway_availability_zones`: Applies only when
  `nat_gateway_mode = "Zonal"`. `null` (default) preserves the automatic
  behavior: create a NAT gateway for every private-subnet AZ, with a public
  subnet required in each. An explicit list, such as `["us-east-1a"]`, limits
  NAT gateways and private NAT routes to those AZs. Every listed AZ must have
  both a public and private subnet; private subnets in unlisted AZs will have
  no NAT route. Use `[]` to explicitly create no Zonal NAT gateways or NAT
  routes.
- `enable_dns_support`: Enables DNS resolution through the Amazon-provided
  resolver in the VPC. Defaults to `true`.
- `enable_dns_hostnames`: Enables DNS hostnames for instances in the VPC.
  Defaults to `true`; keep DNS support enabled as well.
- `tags`: Extra tags applied to resources. The configuration also adds
  `Project` and resource-specific `Name` and `Tier` tags.

The defaults create one public subnet and two private subnets in separate
Availability Zones, with NAT disabled. The public subnet and private subnet in
`us-east-1a` use different CIDR ranges. See
[`terraform.tfvars.example`](./terraform.tfvars.example) for an annotated,
ready-to-copy configuration.

## Deploy

```sh
terraform init \
  -backend-config="bucket=your-state-bucket" \
  -backend-config="key=terraform/vpc/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
terraform plan
terraform apply
```

An existing S3 bucket is required for the backend. The workflow accepts the
bucket and an optional key prefix; it always uses `terraform.tfstate` as the
state file name.

Terraform outputs the VPC ID, optional internet gateway ID, subnet IDs, and
route table IDs.

## Deploy with GitHub Actions

The **Deploy VPC** workflow is manually triggered from the repository's
**Actions** tab using **Run workflow**. Each run creates a Terraform plan and
immediately applies that exact saved plan. There is no plan-only option, and
plan details are not added to the deployment summary; Terraform outputs are
shown there after apply. Every Terraform variable is provided as a workflow
input. Subnets and tags are entered as JSON objects, and
`zonal_nat_gateway_availability_zones` accepts a JSON array, for example:

```json
{
  "public-a": {
    "cidr_block": "10.0.1.0/24",
    "availability_zone": "us-east-1a"
  }
}
```

For that input, use `null` to create Zonal NAT gateways in every private-subnet
AZ, or `["us-east-1a"]` to create one only in `us-east-1a`. Use `[]` for no
Zonal NAT gateways. Private subnets in unlisted AZs will not have a NAT route.
Every AZ in a non-empty list must have both public and private subnets.

Set either subnet input to `{}` to omit that subnet type. Running this workflow
will apply the requested configuration, including creating, updating, or
destroying resources as required by Terraform.

Choose `None`, `Zonal`, or `Regional` for the NAT gateway mode. NAT gateways
can incur significant charges; `None` is the default.

After an `apply`, Terraform outputs are included in the run summary as JSON.
Sensitive outputs, if any are added later, are omitted from the summary.

### Terraform state backend

The workflow requires the **S3 state bucket** input and accepts an optional
**S3 state key prefix**. For example, bucket `my-tf-state` and prefix
`terraform/vpc` store state at `terraform/vpc/terraform.tfstate`. Leave the
prefix empty to store `terraform.tfstate` at the bucket root. The bucket must
already exist; the backend region is the selected AWS region. The workflow
enables S3 encryption and native state locking. Enable bucket versioning for
recovery.

Configure the repository Actions secret `AWS_ROLE_ARN` with an IAM role ARN
trusted for GitHub Actions OIDC. For S3 state, grant the role the necessary
access to the selected bucket and key, in addition to the AWS permissions
needed to manage the VPC. Restrict its OIDC trust policy to this repository and
your allowed branch or environment.

Reuse the same bucket and prefix across runs to manage the same VPC state. If
you have an existing local Terraform state file, migrate it to the S3 backend
before running this workflow; otherwise Terraform may plan to recreate
existing resources.
