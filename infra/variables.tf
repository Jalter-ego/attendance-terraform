variable "aws_region" {
  description = "AWS region of the shared team environment."
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "Optional personal AWS profile override. Normally use AWS_PROFILE locally."
  type        = string
  default     = null
  nullable    = true
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
  description = "Common deployment name. Every teammate must use the same value."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,39}$", var.deployment_name))
    error_message = "Use 3-40 lowercase letters, numbers and hyphens, starting with a letter."
  }
}

variable "ssh_allowed_cidr" {
  description = "Primary operator IPv4 /32, committed as part of the shared configuration."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr)) && endswith(var.ssh_allowed_cidr, "/32")
    error_message = "Use your public IPv4 followed by /32."
  }
}

variable "additional_ssh_allowed_cidrs" {
  description = "Additional approved teammate IPv4 /32 ranges; SSH keys are authorized separately."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.additional_ssh_allowed_cidrs : can(cidrnetmask(cidr)) && endswith(cidr, "/32")])
    error_message = "Each additional SSH address must be a public IPv4 followed by /32."
  }
}

variable "ubuntu_ami_id" {
  description = "Pinned official Ubuntu AMI in the shared region; update through a reviewed plan."
  type        = string
  validation {
    condition     = can(regex("^ami-[a-f0-9]{17}$", var.ubuntu_ami_id))
    error_message = "Provide the pinned Ubuntu AMI ID for the team's region."
  }
}

variable "ssh_public_key_path" {
  description = "Stable bootstrap PUBLIC key in this repository, relative to infra/. Never a private key."
  type        = string
  default     = "keys/operator.pub"
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
  description = "Exact Node.js 24 version installed on the application instances."
  type        = string
  default     = "24.15.0"
  validation {
    condition     = can(regex("^24\\.[0-9]+\\.[0-9]+$", var.node_version))
    error_message = "Provide a Node.js 24 release number."
  }
}

variable "pnpm_version" {
  description = "Exact pnpm version installed on the application instances."
  type        = string
  default     = "10.11.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.pnpm_version))
    error_message = "Provide an exact pnpm release number."
  }
}
