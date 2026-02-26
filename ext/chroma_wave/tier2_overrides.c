/*
 * tier2_overrides.c -- Per-model driver overrides for Tier 2 displays
 *
 * NOTE: Phase 1 scaffolding.  This file is intentionally empty.
 *
 * Real per-model overrides (custom init sequences, LUT loading,
 * non-standard refresh sequences, etc.) will be added here in Phase 2
 * once end-to-end hardware validation is in place for each Tier 2 model.
 *
 * The Tier 2 stub infrastructure (stub_init / stub_display) currently
 * lives in driver_registry.c and delegates to the generic implementation.
 * When real overrides are implemented, they will be defined here and
 * linked into the tier2_drivers table.
 */

#include "driver_registry.h"
