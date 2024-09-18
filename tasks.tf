# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Configuration for Nomad tasks.
#
# Theses resources allow Nomad tasks to exchange their workload identity JSON
# Web Tokens (JWTs) for Consul ACL tokens with a given set of permissions to,
# among other things, access Consul's service catalog and KV store from
# templates.

locals {
  create_default_policy = length(var.tasks_policy_ids) == 0
  tasks_policy_ids      = local.create_default_policy ? consul_acl_policy.tasks[*].id : var.tasks_policy_ids

  # tasks_role_prefix ensures that roles and binding rules are created with
  # compatible names. A mismatch can cause login requests to return 403 errors.
  tasks_role_prefix = "nomad-tasks"
}

# consul_acl_binding_rule.tasks binds consul_acl_auth_method.nomad to a role
# in order to specify the permissions granted to tokens generated by the auth
# method.
#
# Refer to Consul's documentation on binding rules for more information.
# https://developer.hashicorp.com/consul/docs/security/acl/auth-methods#binding-rules
resource "consul_acl_binding_rule" "tasks" {
  auth_method = consul_acl_auth_method.nomad.name
  description = "Binding rule for Nomad tasks"
  bind_type   = "role"
  partition   = var.consul_admin_partition

  # bind_name must match the name of an ACL role to apply to tokens. You may
  # reference values from the ClaimMappings configured in the auth method to
  # make the selection more dynamic.
  #
  # Refer to Consul's documentation on claim mappings for more information.
  # https://developer.hashicorp.com/consul/docs/security/acl/auth-methods/jwt#trusted-identity-attributes-via-claim-mappings
  bind_name = "${local.tasks_role_prefix}-$${value.nomad_namespace}"

  # selector ensures this binding rule is only applied to workload identities
  # for tasks, not services.
  selector = "\"nomad_service\" not in value"
}


# consul_acl_role.tasks is the ACL role that attaches a set of policies and
# permissions to tokens.
#
# Refer to Consul's documentation on ACL roles for more information.
# https://developer.hashicorp.com/consul/docs/security/acl/acl-roles
resource "consul_acl_role" "tasks" {

  # As an example, this module creates different roles for each Nomad namespace
  # to illustrate the use of claim mappings attributes, but this can be
  # adjusted as needed in a real cluster.
  for_each = toset(var.nomad_namespaces)

  # The role name must match the value set in the binding rule bind_name
  # attributes.
  name = "${local.tasks_role_prefix}-${each.key}"

  description = "ACL role for Nomad tasks in the ${each.key} Nomad namespace"
  partition   = var.consul_admin_partition
  policies    = local.tasks_policy_ids
}

# consul_acl_policy.tasks is a sample ACL policy that grants tokens read access
# to Consul's service catalog and KV storage.
#
# This is the policy used in consul_acl_role.tasks if the variable
# tasks_policy_ids is not set.
resource "consul_acl_policy" "tasks" {
  count = local.create_default_policy ? 1 : 0

  name        = var.tasks_default_policy_name
  description = "ACL policy used by Nomad tasks"
  partition   = var.consul_admin_partition

  rules = <<EOF
key_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
EOF
}
