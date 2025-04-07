
variable "project_ids" {
  type = map(string)
}

variable "credentials_file" {
  type = string
  default = "../../firebase-dev.json"
}
