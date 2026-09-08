#include "blade_solver_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstring>

using namespace godot;

/* Transliteration notes — read before "cleaning up" any expression here.
 *
 * The goal is BIT-IDENTICAL agreement with the GDScript path, not merely
 * "close enough". test/unit/attack/test_blade_native_parity.gd pins it at
 * exact equality, and test_melee_swing_characterization.gd would notice drift
 * through the hit set. That is only achievable because every expression below
 * keeps the SAME evaluation order and the SAME real_t/double split as the
 * GDScript it mirrors:
 *
 *   - Vector2 components are real_t (float32). Vector2 * <GDScript float>
 *     narrows the scalar to real_t first, so `(delta * diff) * k` is two
 *     float32 multiplies, NOT one double multiply folded in.
 *   - PackedFloat32Array reads widen to double the moment GDScript stores
 *     them in a `var`, so `wa`, `wb`, `w` are doubles here too. Symmetrically,
 *     a WRITE to PackedFloat32Array narrows: `speeds[i] = sqrt(sp_sq)` is a
 *     double sqrt rounded to float32 on store, which is why `speeds` below is
 *     a float buffer assigned from a double expression.
 *   - length()/length_squared() are real_t; dividing by `dt * dt` (double)
 *     promotes, exactly as GDScript does.
 *   - `int(x)` in GDScript truncates toward zero — C's (int) cast, not floor.
 *     `round()` is half-away-from-zero, which is std::round, NOT rint.
 *
 * Do not add -ffast-math or -march=native. FMA contraction in particular would
 * silently break parity, which is why native/SConstruct pins
 * `-ffp-contract=off` rather than relying on the x86_64 baseline lacking FMA.
 */

// Per-constraint scalar stride in `p_constraint_scalars`: rest, compliance.
static const int CONSTRAINT_STRIDE = 2;
// Per-driver scalar stride in `p_driver_scalars`:
// radius, start_angle, sweep, duration. (Centre rides p_driver_centers so it
// keeps its authored real_t bits.)
static const int DRIVER_STRIDE = 4;

void BladeSolverNative::_bind_methods() {
    ClassDB::bind_method(
            D_METHOD("simulate",
                    "positions", "inv_masses",
                    "constraint_ab", "constraint_scalars",
                    "driver_particles", "driver_centers", "driver_scalars",
                    "duration", "dt", "base_iterations", "velocity_iter_ref",
                    "substeps", "length_factor"),
            &BladeSolverNative::simulate);
}

Dictionary BladeSolverNative::simulate(
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
        double p_length_factor) const {
    const int64_t n = p_positions.size();
    const int64_t constraint_count = p_constraint_ab.size() / 2;
    const int64_t driver_count = p_driver_particles.size();

    // Working buffers. `positions` starts as a copy of the caller's array;
    // `prev` mirrors BladeSim.simulate's `state.prev_positions = positions.duplicate()`.
    PackedVector2Array positions_buf = p_positions;
    PackedVector2Array prev_buf = p_positions;
    Vector2 *positions = positions_buf.ptrw();
    Vector2 *prev = prev_buf.ptrw();

    const float *inv_masses = p_inv_masses.ptr();
    const int32_t *cab = p_constraint_ab.ptr();
    const double *cs = p_constraint_scalars.ptr();
    const int32_t *dp = p_driver_particles.ptr();
    const Vector2 *dc = p_driver_centers.ptr();
    const double *ds = p_driver_scalars.ptr();

    TypedArray<PackedVector2Array> samples;
    // Snapshots must NOT alias `positions_buf`: pushing it would raise its
    // CoW refcount while `positions` (a ptrw() taken once, for speed) keeps
    // writing through the shared buffer, retroactively rewriting every stored
    // sample. Every sample is an explicit fresh copy for that reason.
    PackedVector2Array snap;
    snap.resize(n);
    memcpy(snap.ptrw(), p_positions.ptr(), (size_t)n * sizeof(Vector2));
    // samples[0] is the pose BEFORE any solver step (#633).
    samples.push_back(snap);

    // speed_history[0] parallels samples[0]: zero for every particle, since
    // nothing has stepped yet (#779).
    TypedArray<PackedFloat32Array> speed_history;
    PackedFloat32Array zero_speeds;
    zero_speeds.resize(n);
    memset(zero_speeds.ptrw(), 0, (size_t)n * sizeof(float));
    speed_history.push_back(zero_speeds);

    // Scratch for one substep's speeds. Rewritten in full (statics included)
    // at the top of every substep, and copied out only after the substep loop
    // — the sample carries the LAST substep's speeds, deliberately not an
    // average and not the interval's max (#779).
    PackedFloat32Array speeds_buf;
    speeds_buf.resize(n);
    float *speeds = speeds_buf.ptrw();

    const int steps = (int)Math::ceil(p_duration / p_dt);
    // BladeSim.simulate's `var sub := maxi(substeps, 1)`.
    const int64_t sub = p_substeps > 1 ? p_substeps : 1;
    const double sub_dt = p_dt / (double)sub;
    const double sub_dt_sq = sub_dt * sub_dt;

    for (int step = 0; step < steps; step++) {
        const double t0 = (double)step * p_dt;

        for (int64_t s = 0; s < sub; s++) {
            const double t = t0 + (double)(s + 1) * sub_dt;
            memset(speeds, 0, (size_t)n * sizeof(float));

            // --- Verlet integrate dynamic particles; track max speed. ---
            double max_speed_sq = 0.0;
            for (int64_t i = 0; i < n; i++) {
                if ((double)inv_masses[i] > 0.0) {
                    const Vector2 p = positions[i];
                    const Vector2 v = p - prev[i];
                    prev[i] = p;
                    positions[i] = p + v;
                    const real_t v_len_sq = v.x * v.x + v.y * v.y;
                    const double sp_sq = (double)v_len_sq / sub_dt_sq;
                    speeds[i] = (float)Math::sqrt(sp_sq);
                    if (sp_sq > max_speed_sq) {
                        max_speed_sq = sp_sq;
                    }
                } else {
                    prev[i] = positions[i];
                }
            }

            // --- Drivers override prescribed particles (BladeArcDriver.apply). ---
            for (int64_t d = 0; d < driver_count; d++) {
                const double radius = ds[d * DRIVER_STRIDE + 0];
                const double start_angle = ds[d * DRIVER_STRIDE + 1];
                const double sweep = ds[d * DRIVER_STRIDE + 2];
                const double duration = ds[d * DRIVER_STRIDE + 3];
                const double f = duration > 0.0 ? Math::clamp(t / duration, 0.0, 1.0) : 0.0;
                // _sine_in_out — the one deliberate transcendental (#547).
                const double eased = 0.5 - 0.5 * Math::cos(Math::PI * f);
                const double angle = start_angle + sweep * eased;
                const Vector2 unit((real_t)Math::cos((real_t)angle), (real_t)Math::sin((real_t)angle));
                positions[dp[d]] = dc[d] + unit * (real_t)radius;
            }

            // --- Sweep budget for this SAMPLE INTERVAL: velocity axis, then
            // the #790 blade-length axis, then split across the substeps
            // composing the interval. Note the budget is computed per SUBSTEP
            // here exactly as GDScript does (max_speed_sq is this substep's),
            // but the divisor is the interval's substep count. ---
            double budget = (double)p_base_iterations;
            if (p_velocity_iter_ref > 0.0) {
                const double max_speed = Math::sqrt(max_speed_sq);
                budget *= 1.0 + max_speed / p_velocity_iter_ref;
            }
            budget *= p_length_factor;
            int iters = (int)Math::round(budget / (double)sub);
            if (iters < 1) {
                iters = 1;
            }

            // --- Project constraints (BladeDistanceConstraint.project). ---
            for (int it = 0; it < iters; it++) {
                for (int64_t c = 0; c < constraint_count; c++) {
                    const int32_t a = cab[c * 2 + 0];
                    const int32_t b = cab[c * 2 + 1];
                    const Vector2 pa = positions[a];
                    const Vector2 pb = positions[b];
                    const Vector2 delta = pb - pa;
                    const double dist = (double)Math::sqrt(delta.x * delta.x + delta.y * delta.y);
                    if (dist < 1e-6) {
                        continue;
                    }
                    const double wa = (double)inv_masses[a];
                    const double wb = (double)inv_masses[b];
                    const double w = wa + wb;
                    if (w == 0.0) {
                        continue;
                    }
                    const double rest = cs[c * CONSTRAINT_STRIDE + 0];
                    const double compliance = cs[c * CONSTRAINT_STRIDE + 1];
                    const double k = 1.0 / (1.0 + compliance);
                    const double diff = (dist - rest) / dist;
                    const Vector2 corr = (delta * (real_t)diff) * (real_t)k;
                    positions[a] = pa + corr * (real_t)(wa / w);
                    positions[b] = pb - corr * (real_t)(wb / w);
                }
            }
        }

        // One sample per `dt`, never one per substep — hit-scan cost stays
        // independent of the substep knob (#790).
        PackedVector2Array step_snap;
        step_snap.resize(n);
        memcpy(step_snap.ptrw(), positions, (size_t)n * sizeof(Vector2));
        samples.push_back(step_snap);

        PackedFloat32Array speed_snap;
        speed_snap.resize(n);
        memcpy(speed_snap.ptrw(), speeds, (size_t)n * sizeof(float));
        speed_history.push_back(speed_snap);
    }

    // The caller writes these straight back onto its BladeState, so
    // simulate()'s in-place mutation contract survives the round trip.
    Dictionary out;
    out["samples"] = samples;
    out["speed_history"] = speed_history;
    out["positions"] = positions_buf;
    out["prev_positions"] = prev_buf;
    return out;
}
