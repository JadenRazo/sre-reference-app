# tflint config for the infra/ tree.
# Loads the AWS plugin so provider-specific rules fire (deprecated args,
# unsupported instance types, missing required attributes, etc.).
# `tflint --init` resolves and downloads the plugin in CI.

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.47.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

# `terraform_required_version` is set in providers.tf at the root.
# Submodules inherit the root constraint; tflint's per-module check is noisy.
rule "terraform_required_version" {
  enabled = false
}
