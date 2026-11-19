# State bucket is created out-of-band (see README "Bootstrap the state
# backend"). No bucket/region here since this file is committed to git:
#
#   terraform init \
#     -backend-config="bucket=<your-state-bucket>" \
#     -backend-config="key=knative-serving/terraform.tfstate" \
#     -backend-config="region=<your-region>" \
#     -backend-config="use_lockfile=true"   # or dynamodb_table=<table> on Terraform < 1.10
terraform {
  backend "s3" {
    encrypt = true
  }
}
