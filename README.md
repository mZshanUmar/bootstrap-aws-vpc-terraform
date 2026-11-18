# Terraform AWS VPC

A variable-driven Terraform template for an AWS VPC with configurable public and
private subnets. Each subnet gets its own route table. Public subnets get
internet-gateway routes; Regional NAT mode also creates an internet gateway
when no public subnets are configured.

## Requirements

- Terraform 1.5 or later
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
```

Add or remove entries in either subnet map to control the number of subnets.
Each map key becomes the subnet's `Name` tag; set its CIDR and availability
zone in the value. Set either map to `{}` to create no subnets of that type.
An internet gateway is created when public subnets exist or Regional NAT mode
is selected.

Public subnets receive a default route to the internet gateway and assign public
IPv4 addresses on launch. Each private subnet has its own route table and no
internet default route unless NAT gateways are enabled.

Set `nat_gateway_mode` to `None` (default), `Zonal`, or `Regional` to control
private-subnet internet access. `Zonal` creates a NAT gateway in each AZ that
has private subnets and requires a public subnet in each such AZ. `Regional`
creates one native AWS Regional NAT Gateway. NAT gateways incur hourly and
data-processing charges. Set `enable_s3_endpoint = true` to add an S3 gateway
endpoint to the private route tables; it requires at least one private subnet.
Optional variables also include `enable_dns_support`, `enable_dns_hostnames`,
and `tags`. See `variables.tf` for defaults and descriptions.

## Deploy

```sh
terraform init
terraform plan
terraform apply
```

Terraform outputs the VPC ID, optional internet gateway ID, subnet IDs, and
route table IDs.

## Deploy with GitHub Actions

The **Deploy VPC** workflow is manually triggered from the repository's
**Actions** tab using **Run workflow**. Choose `plan` to review changes without
applying them, or `apply` to create/update the VPC. Every Terraform variable is
provided as a workflow input. Subnets and tags are entered as JSON objects, for
example:

```json
{
  "public-a": {
    "cidr_block": "10.0.1.0/24",
    "availability_zone": "us-east-1a"
  }
}
```

Set either subnet input to `{}` to omit that subnet type. The `apply` action uses
the same workflow job as `plan`; choose `apply` only when you intend Terraform
to create or update infrastructure.

Choose `None`, `Zonal`, or `Regional` for the NAT gateway mode and whether to
create an S3 gateway endpoint in the workflow inputs. NAT gateways can incur
significant charges; `None` is the default.

Configure the repository Actions secret `AWS_ROLE_ARN` with an IAM role ARN
trusted for GitHub Actions OIDC. Grant that role only the AWS permissions needed
to manage this VPC, and restrict its OIDC trust policy to this repository and
your allowed branch or environment.

**State warning:** this workflow uses Terraform's local state on an ephemeral
GitHub runner and does not preserve it after a run. It is suitable only for a
one-time deployment as requested; later runs cannot reliably manage or destroy
resources created by an earlier run. Use a persistent remote backend such as
S3 before relying on repeatable deployments or updates.
