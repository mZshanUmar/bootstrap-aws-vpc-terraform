# Terraform AWS VPC

A variable-driven Terraform template for an AWS VPC with configurable public and
private subnets. Each subnet gets its own route table. An internet gateway and
default internet routes are created only when at least one public subnet is
configured.

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
}
```

Add or remove entries in either subnet map to control the number of subnets.
Each map key becomes the subnet's `Name` tag; set its CIDR and availability
zone in the value. Set either map to `{}` to create no subnets of that type.
When `public_subnets` is empty, no internet gateway is created.

Public subnets receive a default route to the internet gateway and assign public
IPv4 addresses on launch. Each private subnet has its own route table with no
internet default route; this template does not create NAT gateways.

Optional variables include `enable_dns_support`, `enable_dns_hostnames`, and
`tags`. See `variables.tf` for defaults and descriptions.

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
the `vpc-deploy` GitHub Environment; configure required reviewers for that
environment to gate deployments. The `plan` action uses `vpc-plan` and does not
require approval by default.

Configure the repository Actions secret `AWS_ROLE_ARN` with an IAM role ARN
trusted for GitHub Actions OIDC. Grant that role only the AWS permissions needed
to manage this VPC, and restrict its OIDC trust policy to this repository and
your allowed branch or environment.

**State warning:** this workflow uses Terraform's local state on an ephemeral
GitHub runner and does not preserve it after a run. It is suitable only for a
one-time deployment as requested; later runs cannot reliably manage or destroy
resources created by an earlier run. Use a persistent remote backend such as
S3 before relying on repeatable deployments or updates.
