# Per-account overrides. Picked up automatically by terraform plan/apply.
#
# enable_fis = false because this AWS account returns
# SubscriptionRequiredException on aws_fis_experiment_template create. The
# chaos phase substitutes `aws ecs stop-task` (same blast radius, $0 cost,
# no service-onboarding gate). Set to true and re-apply if the account
# state changes (e.g. after a support ticket or after the account ages
# past the new-account onboarding window).
enable_fis = false
