locals {
  # Standard MWMBR thresholds: fast-burn 14.4x over 1h, slow-burn 6x over 6h.
  # See docs/slos.md for the math.
  fast_burn_threshold = (1 - var.slo_target) * 14.4
  slow_burn_threshold = (1 - var.slo_target) * 6
}
