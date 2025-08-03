variable "profile" {
  type        = string
  description = "AWS profile"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "namespace" {
  type        = string
  description = "ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique"
}

variable "name" {
  type        = string
  description = "ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'."
}