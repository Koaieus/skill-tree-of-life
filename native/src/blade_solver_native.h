/* Native blade PBD solver — the C++ half of #798.
 *
 * See docs/domain/melee-blade-sim.md ("Backends") and attack/melee/sim/blade_sim.gd.
 * This file mirrors BladeSim.simulate_range + BladeSim._step +
 * BladeDistanceConstraint.project ONLY (simulate() is the whole-swing
 * reduction of simulate_range, on both sides). BladeHitScan is deliberately not here:
 * it touches the physics server.
 *
 * `p_length_factor` arrives PRECOMPUTED from GDScript (BladeSim._length_factor
 * over BladeState.pivot_eccentricity()). The BFS behind it runs once per
 * resolve, not per step, so porting it would buy nothing measurable and would
 * put the #790 length axis's definition in two places.
 */
#ifndef BLADE_SOLVER_NATIVE_H
#define BLADE_SOLVER_NATIVE_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

class BladeSolverNative : public RefCounted {
    GDCLASS(BladeSolverNative, RefCounted)

protected:
    static void _bind_methods();

public:
    // Pure: no member state is touched, so one shared instance is safe to call
    // from every WorkerThreadPool task AiBladeRollout spawns.
    //
    // The whole-swing shape (#798): Verlet history at rest, step 0,
    // ceil(duration / dt) steps, no damping. Kept verbatim as the additive
    // contract #803 promised; it is simulate_range with those inputs and
    // nothing else, exactly as BladeSim.simulate is to BladeSim.simulate_range.
    Dictionary simulate(
            const PackedVector2Array &p_positions,
            const PackedFloat32Array &p_inv_masses,
            const PackedInt32Array &p_constraint_ab,
            const PackedFloat64Array &p_constraint_scalars,
            const PackedInt32Array &p_driver_particles,
            const PackedVector2Array &p_driver_centers,
            const PackedFloat64Array &p_driver_scalars,
            double p_duration,
            double p_dt,
            int64_t p_base_iterations,
            double p_velocity_iter_ref,
            int64_t p_substeps,
            double p_length_factor) const;

    // THE stepping loop (#803) — BladeSim.simulate_range transliterated.
    // Continues from `p_prev_positions` as given (the caller resets it to
    // `p_positions` for a run starting at rest), runs `p_step_count` steps
    // whose GLOBAL index starts at `p_step_offset`, and bleeds each particle's
    // velocity by `p_damping[i]` per second when that array is non-empty.
    //
    // `p_step_offset` is an INTEGER and that is load-bearing: every substep's
    // time is `(double)(step_offset + local) * dt + (double)(s + 1) * sub_dt`,
    // so a run split into chunks is bit-identical to the unchunked one. A
    // float time origin carried across chunks would not be.
    //
    // Returns, parallel to `samples`, a `prev_samples` array: the Verlet
    // history AFTER each step — a mid-sample pose (`prev` is rewritten per
    // substep) that is not derivable from `samples` and is what a severance
    // rewinds onto.
    Dictionary simulate_range(
            const PackedVector2Array &p_positions,
            const PackedVector2Array &p_prev_positions,
            const PackedFloat32Array &p_inv_masses,
            const PackedInt32Array &p_constraint_ab,
            const PackedFloat64Array &p_constraint_scalars,
            const PackedInt32Array &p_driver_particles,
            const PackedVector2Array &p_driver_centers,
            const PackedFloat64Array &p_driver_scalars,
            const PackedFloat32Array &p_damping,
            int64_t p_step_offset,
            int64_t p_step_count,
            double p_dt,
            int64_t p_base_iterations,
            double p_velocity_iter_ref,
            int64_t p_substeps,
            double p_length_factor) const;

    // The same stepping loop with a BladeSwingClock and/or a BladeObstacleField
    // riding along (#813) — what a swing near ANY defender takes, which since
    // #811 is most of them.
    //
    // `p_field` is the IMMUTABLE half of the run: the zone set
    // (BladeDefenderZones' four parallel arrays), the live edge set, the driven
    // particles and the particle->incident-edge CSR that
    // BladeObstacleField.prepare() just built, plus the four tuning constants
    // (CONTACT_SLOP / CONTACT_HYSTERESIS / SHATTER_DISTANCE / EDGE_RADIUS) —
    // passed rather than duplicated so each keeps ONE definition, in GDScript.
    //
    // `p_sim` is the MUTABLE half: BladeSwingClock's six fields and
    // BladeObstacleField.Bank's eight, as plain values. They come back advanced
    // in `clock_state` / `field_state`, plus one Bank-shaped Dictionary per
    // sample in `clock_history` / `field_history` — the resolve loop's rewind
    // reads all of it, so a missing key here is a silently un-rewindable swing.
    //
    // Shaped as "zones in -> contacts + pushout out": the zone set crosses as
    // plain arrays that any consumer can read, not as a solver-private blob, so
    // an analytic BladeHitScan could later be built on the same input.
    Dictionary simulate_range_field(
            const PackedVector2Array &p_positions,
            const PackedVector2Array &p_prev_positions,
            const PackedFloat32Array &p_inv_masses,
            const PackedInt32Array &p_constraint_ab,
            const PackedFloat64Array &p_constraint_scalars,
            const PackedInt32Array &p_driver_particles,
            const PackedVector2Array &p_driver_centers,
            const PackedFloat64Array &p_driver_scalars,
            const PackedFloat32Array &p_damping,
            int64_t p_step_offset,
            int64_t p_step_count,
            double p_dt,
            int64_t p_base_iterations,
            double p_velocity_iter_ref,
            int64_t p_substeps,
            double p_length_factor,
            const Dictionary &p_field,
            const Dictionary &p_sim) const;
};

} // namespace godot

#endif // BLADE_SOLVER_NATIVE_H
