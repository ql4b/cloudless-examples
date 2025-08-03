output "env" {
  value = {
    account_id = local.account_id
    id         = local.id
    name       = local.name
    namespace  = local.namespace
    profile    = local.profile
    region     = local.region
  }
}

output "lambda" {
  value = module.lambda_function
}

output "runtime" {
  value = module.lambda_runtime
}

output "source_bucket" {
  value = module.source_bucket
}

output "thumbnails_bucket" {
  value = module.thumbnails_bucket
}