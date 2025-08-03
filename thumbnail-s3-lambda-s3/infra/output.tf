output env {
    value = {
        profile = local.profile
        region = local.region
        namespace = module.label.namespace
        name = module.label.name
        id = module.label.id
        account_id = local.account_id
    }
}

output runtime {
    value = module.lambda_runtime
}

output lambda {
    value = module.lambda_function

}

output source_bucket {
  value = module.source_bucket
}

output thumbnails_bucket {
  value = module.thumbnails_bucket
}