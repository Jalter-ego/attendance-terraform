variable "aws_region" {
  description = "AWS region for this independent lab."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Local AWS CLI profile; credentials never go in this repository."
  type        = string
  default     = "attendance-terraform"
}

variable "aws_account_id" {
  description = "Expected AWS account ID, to prevent deploying into another account."
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "Provide the 12-digit AWS account ID."
  }
}

variable "deployment_name" {
  description = "Unique name per classmate/tool, for example attendance-tf-jeanne."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.deployment_name))
    error_message = "Use 3-40 lowercase letters, numbers and hyphens, starting with a letter."
  }
}

variable "ssh_allowed_cidr" {
  description = "Your public IPv4 as a /32. SSH must not be exposed to the whole internet."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && endswith(var.ssh_allowed_cidr, "/32")
    error_message = "Use your public IPv4 followed by /32."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the local EC2 access PUBLIC key (.pub)."
  type        = string
  default     = "../.local/ssh/attendance-terraform.pub"
}

variable "instance_type" {
  description = "Instance size. Two t3.small instances provide 2 GiB each for builds."
  type        = string
  default     = "t3.small"
  validation {
    condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "This lab supports x86_64 t3.micro, t3.small or t3.medium instances."
  }
}

variable "node_version" {
  type    = string
  default = "24.15.0"
  validation {
    condition     = can(regex("^24\\.[0-9]+\\.[0-9]+$", var.node_version))
    error_message = "Provide a Node.js 24 release number."
  }
}

variable "pnpm_version" {
  type    = string
  default = "10.11.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.pnpm_version))
    error_message = "Provide an exact pnpm release number."
  }
}
