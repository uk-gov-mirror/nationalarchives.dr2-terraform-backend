variable "environments" {
  type    = list(string)
  default = []
}

variable "repositories" {
  type = list(object({ name : string, branch : optional(string, "main") }))
}

variable "organisation" {
  default = "nationalarchives@10154228"
}