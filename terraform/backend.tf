# Remote state in S3, encrypted at rest, versioned, with state locking.
#
# The bucket and lock mechanism are created out-of-band (chicken-and-egg problem
# with a Terraform-managed backend) — see README.md "Bootstrap the state backend".
# It must have:
#   - versioning enabled
#   - default encryption with a customer-managed KMS key
#   - a bucket policy that denies non-TLS (aws:SecureTransport=false) requests
#   - all public access blocked
#
# No bucket/region values are hardcoded here on purpose (they are account-specific
# and this file is committed to git). Initialize with:
#
#   terraform init \
#     -backend-config="bucket=<your-state-bucket>" \
#     -backend-config="key=knative-serving/terraform.tfstate" \
#     -backend-config="region=<your-region>" \
#     -backend-config="kms_key_id=<your-kms-key-arn-or-alias>" \
#     -backend-config="dynamodb_table=<your-lock-table>"   # omit if using Terraform >= 1.10 native S3 locking + use_lockfile=true
terraform {
  backend "s3" {
    encrypt = true
  }
}
