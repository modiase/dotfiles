variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west2"
}

variable "functions_bucket" {
  type = string
}

variable "ntfy_topic_id" {
  type = string
}

variable "ntfy_topic_name" {
  type = string
}

variable "name" {
  type = string
}

variable "bucket" {
  type = string
}

variable "object" {
  type = string
}

variable "schedule" {
  type = string
}

variable "max_age_hours" {
  type = number
}

variable "ntfy_topic" {
  type = string
}

variable "ntfy_priority" {
  type    = string
  default = "3"
}

variable "ntfy_title" {
  type = string
}

variable "ntfy_message" {
  type = string
}
