/* Native blade PBD solver — the C++ half of #798.
 *
 * See docs/domain/melee-blade-sim.md ("Backends") and attack/melee/sim/blade_sim.gd.
 * This file mirrors BladeSim.simulate + BladeSim._step +
 * BladeDistanceConstraint.project ONLY. BladeHitScan is deliberately not here:
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
};

} // namespace godot

#endif // BLADE_SOLVER_NATIVE_H
