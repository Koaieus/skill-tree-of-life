#include "blade_solver_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <cstring>

using namespace godot;

/* Transliteration notes — read before "cleaning up" any expression here.
 *
 * This is a transliteration of the GDScript solver it replaced (#847), and
 * the recorded goldens in test/unit/attack/test_blade_goldens.gd pin it BIT-
 * IDENTICAL to what that solver produced; test_melee_swing_characterization.gd
 * would notice drift through the hit set. Those goldens only hold because
 * every expression below keeps the SAME evaluation order and the SAME
 * real_t/double split as the GDScript it was transliterated from:
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

/* ── The defender half (#813) ─────────────────────────────────────────────────
 *
 * BladeSwingClock + BladeObstacleField, transliterated under the same rules as
 * everything above. Three notes that only apply down here:
 *
 *   - `_strain` is a PackedFloat32Array whose arithmetic is double: the read
 *     widens, the add and the maxf happen in double, the STORE narrows, and the
 *     `< SHATTER_DISTANCE` test then compares the narrowed value. Keeping a
 *     double accumulator "for accuracy" is a different solver. `_edge_residual`
 *     is the opposite — its values are plain GDScript floats, i.e. doubles.
 *   - `_contact_particles` / `_contact_edges` / `_contact_normals` are godot
 *     Dictionaries here for the same reason they are in GDScript: iteration is
 *     INSERTION order, and the load-share pass sums into shared edge banks in
 *     that order. A particle touched by zone 3 and then zone 7 keeps zone 7's
 *     value at zone 3's position — a key-sorted map is NOT equivalent.
 *   - The pushout mutates `positions` in place mid-loop: zone z+1 sees zone z's
 *     correction, and zone z's capsule pass sees zone z's own disc pushouts.
 *     Batching the pushes and applying them at the end is a different solver.
 */
namespace {

struct FieldCtx {
    // ── Immutable for this call (BladeObstacleField.native_inputs) ──────────
    const Vector2 *zone_centers = nullptr;
    const float *zone_radii = nullptr;
    const float *zone_drags = nullptr;
    const uint8_t *zone_deflects = nullptr;
    int64_t zone_count = 0;

    const int32_t *edges = nullptr; // 2 int32 per edge: x, y
    const uint8_t *edge_removed = nullptr;
    int64_t edge_count = 0;

    const float *vertex_radii = nullptr;
    int64_t vertex_radii_count = 0;

    const int32_t *driven = nullptr;
    int64_t driven_count = 0;
    Dictionary driven_set;

    // particle -> live incident edge indices, CSR. Flattened from the
    // Dictionary prepare() built, in its ascending-edge-index order — which is
    // summation order for the load share, not merely a layout.
    const int32_t *incident_offsets = nullptr; // size n + 1
    const int32_t *incident_edges = nullptr;

    double contact_slop = 0.0;
    double contact_hysteresis = 0.0;
    double shatter_distance = 0.0;
    double edge_radius = 0.0;

    bool has_field = false;
    bool has_clock = false;

    // ── BladeSwingClock's mutable half ──────────────────────────────────────
    double clock_duration = 0.0;
    double clock_f = 0.0;
    double clock_drag = 0.0;
    double clock_last_t = 0.0;
    bool clock_warping = false;
    bool clock_stalled = false;
    Dictionary clock_touched;

    // ── BladeObstacleField.Bank ─────────────────────────────────────────────
    PackedFloat32Array strain;
    Array edge_residual; // one Dictionary{edge_idx: double} per zone
    PackedVector2Array driven_last;
    PackedVector2Array driven_last_target;
    int64_t break_edge = -1;
    int64_t break_step = -1;
    int64_t break_zone = -1;
    int64_t current_step = 0;

    // ── Per-substep scratch ─────────────────────────────────────────────────
    PackedVector2Array driven_targets;
    Dictionary contact_particles;
    Dictionary contact_edges;
    Dictionary contact_normals;
    Dictionary near_plates;

    // ── Per-sample history, parallel to `samples[1..]` ──────────────────────
    Array clock_history;
    Array field_history;
};

// BladeSwingClock.warp()
double clock_warp(const FieldCtx &f) {
    if (f.clock_stalled) {
        return 0.0;
    }
    return 1.0 / (1.0 + f.clock_drag);
}

// The first-contact seed shared by bank_drag() and stall(): the accumulator
// takes over from the nominal progress the drivers have been reading, so drag
// slows the REST of the arc and never the approach to its own zone.
void clock_seed(FieldCtx &f) {
    f.clock_warping = true;
    f.clock_f = f.clock_duration > 0.0
            ? Math::clamp(f.clock_last_t / f.clock_duration, 0.0, 1.0)
            : 0.0;
}

// BladeSwingClock.tick() — once per SUBSTEP, before the drivers apply.
void clock_tick(FieldCtx &f, double t, double sub_dt) {
    f.clock_last_t = t;
    if (!f.clock_warping || f.clock_duration <= 0.0) {
        return;
    }
    const double advanced = f.clock_f + (sub_dt / f.clock_duration) * clock_warp(f);
    f.clock_f = 1.0 < advanced ? 1.0 : advanced; // minf(1.0, ...)
}

void clock_bank_drag(FieldCtx &f, int64_t z, double amount) {
    if (amount <= 0.0 || f.clock_touched.has(z)) {
        return;
    }
    f.clock_touched[z] = true;
    f.clock_drag += amount;
    if (!f.clock_warping) {
        clock_seed(f);
    }
}

void clock_stall(FieldCtx &f) {
    if (f.clock_stalled) {
        return;
    }
    f.clock_stalled = true;
    if (!f.clock_warping) {
        clock_seed(f);
    }
}

// BladeSwingClock.progress() — -1.0 means "use your own t / duration".
double clock_progress(const FieldCtx &f) {
    return f.clock_warping ? f.clock_f : -1.0;
}

// BladeObstacleField.after_drivers(). ptrw() is taken FRESH rather than cached:
// these buffers get snapshotted into banks, and a stale write pointer would
// retroactively rewrite every snapshot.
void field_after_drivers(FieldCtx &f, const Vector2 *positions) {
    Vector2 *targets = f.driven_targets.ptrw();
    for (int64_t k = 0; k < f.driven_count; k++) {
        targets[k] = positions[f.driven[k]];
    }
}

// BladeObstacleField.project() — the pushout, and the swing's only contact test.
void field_project(FieldCtx &f, Vector2 *positions, const float *inv_masses, int64_t n) {
    if (n == 0 || f.zone_count == 0) {
        return;
    }
    // Broad phase from THIS iteration's positions, so it needs no margin.
    Vector2 lo = positions[0];
    Vector2 hi = positions[0];
    double widest = 0.0;
    for (int64_t i = 0; i < n; i++) {
        lo = lo.min(positions[i]);
        hi = hi.max(positions[i]);
        if (i < f.vertex_radii_count) {
            const double r = (double)f.vertex_radii[i];
            widest = widest > r ? widest : r;
        }
    }
    const double pad = widest + f.edge_radius + f.contact_hysteresis;
    lo -= Vector2((real_t)pad, (real_t)pad);
    hi += Vector2((real_t)pad, (real_t)pad);

    for (int64_t z = 0; z < f.zone_count; z++) {
        const Vector2 c = f.zone_centers[z];
        const double zr = (double)f.zone_radii[z];
        if ((double)c.x < (double)lo.x - zr || (double)c.x > (double)hi.x + zr
                || (double)c.y < (double)lo.y - zr || (double)c.y > (double)hi.y + zr) {
            continue;
        }
        const bool deflect = f.zone_deflects[z] != 0;
        const double drag_amount = (double)f.zone_drags[z];
        // A wall that has already banked has nothing left to learn. The latch
        // lives on the clock; this class keeps no second one.
        bool wants_drag = drag_amount > 0.0 && f.has_clock && !f.clock_touched.has(z);
        if (!deflect && !wants_drag) {
            continue;
        }
        for (int64_t i = 0; i < n; i++) {
            const Vector2 p = positions[i];
            const double pr = i < f.vertex_radii_count ? (double)f.vertex_radii[i] : 0.0;
            const double d2 = (double)p.distance_squared_to(c);
            // Sensed BEFORE the inv_mass skip below: a fortified node
            // overlapping the pivot dragged under #780 and still does.
            if (wants_drag) {
                const double touch = zr + pr;
                if (d2 <= touch * touch) {
                    clock_bank_drag(f, z, drag_amount);
                    wants_drag = false;
                }
            }
            if (!deflect) {
                continue;
            }
            if ((double)inv_masses[i] <= 0.0) {
                continue; // the pivot, or a corpse — neither is pushed
            }
            const double reach = zr + pr - f.contact_slop;
            const double band = reach + f.contact_hysteresis;
            if (d2 >= band * band) {
                continue;
            }
            // Near-but-not-pushed is a real state: it holds the contact open
            // across the substeps a jammed blade jitters through the slop band.
            f.near_plates[z] = true;
            if (d2 >= reach * reach) {
                continue;
            }
            const double d = Math::sqrt(d2);
            const Vector2 normal = d > 1e-6 ? (p - c) / (real_t)d : Vector2(1, 0);
            positions[i] = c + normal * (real_t)reach;
            f.contact_particles[i] = z;
            f.contact_normals[i] = normal;
        }
        if (!deflect && !wants_drag) {
            continue; // wall, already banked by a disc — skip the capsule pass
        }
        const double cap_reach = zr + f.edge_radius;
        for (int64_t e_idx = 0; e_idx < f.edge_count; e_idx++) {
            if (f.edge_removed[e_idx] != 0) {
                continue; // severed — a gone edge touches nothing
            }
            const int32_t ex = f.edges[e_idx * 2 + 0];
            const int32_t ey = f.edges[e_idx * 2 + 1];
            const Vector2 a = positions[ex];
            const Vector2 b = positions[ey];
            const Vector2 delta = b - a;
            const double length = (double)delta.length();
            const double rx = (double)f.vertex_radii[ex];
            const double ry = (double)f.vertex_radii[ey];
            const double trimmed = length - rx - ry;
            if (trimmed < 1e-4) {
                continue; // discs overlap — no exposed span
            }
            const Vector2 dir = delta / (real_t)length;
            const Vector2 p0 = a + dir * (real_t)rx;
            const Vector2 seg = dir * (real_t)trimmed;
            const double u = Math::clamp(
                    (double)(c - p0).dot(seg) / (trimmed * trimmed), 0.0, 1.0);
            const Vector2 q = p0 + seg * (real_t)u;
            const double d2 = (double)q.distance_squared_to(c);
            if (wants_drag && d2 <= cap_reach * cap_reach) {
                clock_bank_drag(f, z, drag_amount);
                wants_drag = false;
                if (!deflect) {
                    break;
                }
            }
            if (!deflect) {
                continue;
            }
            const double wa = (double)inv_masses[ex];
            const double wb = (double)inv_masses[ey];
            if (wa + wb <= 0.0) {
                continue;
            }
            const double cband = cap_reach + f.contact_hysteresis;
            if (d2 >= cband * cband) {
                continue;
            }
            f.near_plates[z] = true;
            if (d2 >= cap_reach * cap_reach) {
                continue;
            }
            const double d = Math::sqrt(d2);
            const Vector2 normal = d > 1e-6 ? (q - c) / (real_t)d : Vector2(-dir.y, dir.x);
            const Vector2 push = normal * (real_t)(cap_reach - d);
            // q's barycentric coordinate along the FULL a..b segment.
            const double sfrac = (rx + trimmed * u) / length;
            const double wa_s = (1.0 - sfrac) * wa;
            const double wb_s = sfrac * wb;
            const double denom = (1.0 - sfrac) * wa_s + sfrac * wb_s;
            if (denom <= 0.0) {
                continue;
            }
            positions[ex] = a + push * (real_t)(wa_s / denom);
            positions[ey] = b + push * (real_t)(wb_s / denom);
            f.contact_edges[e_idx] = z;
        }
    }
}

// BladeObstacleField._bank_load() — the values are GDScript floats, i.e.
// doubles, unlike `strain`.
void field_bank_load(FieldCtx &f, int64_t z, int64_t e_idx, double r) {
    Dictionary d = f.edge_residual[z];
    const double prev = d.has(e_idx) ? (double)d[e_idx] : 0.0;
    d[e_idx] = prev + r;
}

// BladeObstacleField._pick_edge() — most strained LIVE edge, lowest index on a
// tie (ascending keys plus a strict `>`).
int64_t field_pick_edge(const FieldCtx &f, int64_t z) {
    Dictionary d = f.edge_residual[z];
    Array keys = d.keys();
    keys.sort();
    int64_t best = -1;
    double best_r = -1.0;
    for (int64_t i = 0; i < keys.size(); i++) {
        const int64_t e_idx = keys[i];
        if (f.edge_removed[e_idx] != 0) {
            continue;
        }
        const double r = d[keys[i]];
        if (r > best_r) {
            best_r = r;
            best = e_idx;
        }
    }
    return best;
}

void field_roll_driven(FieldCtx &f, const Vector2 *positions) {
    f.driven_last.resize(f.driven_count);
    f.driven_last_target.resize(f.driven_count);
    Vector2 *last = f.driven_last.ptrw();
    Vector2 *last_target = f.driven_last_target.ptrw();
    const Vector2 *targets = f.driven_targets.ptr();
    for (int64_t k = 0; k < f.driven_count; k++) {
        last[k] = positions[f.driven[k]];
        last_target[k] = targets[k];
    }
    f.contact_particles.clear();
    f.contact_edges.clear();
    f.contact_normals.clear();
    f.near_plates.clear();
}

// BladeObstacleField.end_substep() — stall the clock on a grip contact, meter
// the driver residual, bank the load share, arm a break, roll the history.
void field_end_substep(FieldCtx &f, const Vector2 *positions) {
    const int64_t zn = f.strain.size();
    if (f.near_plates.is_empty()) {
        // Nothing near a plate: every contact is over. Reset, don't bank.
        for (int64_t z = 0; z < zn; z++) {
            if (f.strain[z] != 0.0f) {
                f.strain.set(z, 0.0f);
                Dictionary(f.edge_residual[z]).clear();
            }
        }
        field_roll_driven(f, positions);
        return;
    }
    if (f.has_clock) {
        const Array contacts = f.contact_particles.keys();
        for (int64_t ci = 0; ci < contacts.size(); ci++) {
            if (f.driven_set.has(contacts[ci])) {
                clock_stall(f);
                break;
            }
        }
    }
    // The unresolved drive: the most any grip particle fell short of the
    // advance its DRIVER made this substep, measured along that advance.
    double unresolved = 0.0;
    bool any = false;
    if (f.driven_last.size() == f.driven_count) {
        const Vector2 *targets = f.driven_targets.ptr();
        const Vector2 *last = f.driven_last.ptr();
        const Vector2 *last_target = f.driven_last_target.ptr();
        for (int64_t k = 0; k < f.driven_count; k++) {
            const Vector2 want = targets[k] - last_target[k];
            const double req = (double)want.length();
            if (req <= 1e-6) {
                continue;
            }
            const double along = (double)(positions[f.driven[k]] - last[k])
                                         .dot(want / (real_t)req);
            const double got = 0.0 > along ? 0.0 : along;
            const double u = req - got;
            unresolved = !any ? u : (unresolved > u ? unresolved : u);
            any = true;
        }
    }
    for (int64_t z = 0; z < zn; z++) {
        if (f.near_plates.has(z)) {
            // Read widens f32 -> double, add and clamp in double, STORE narrows.
            const double s = (double)f.strain[z] + unresolved;
            f.strain.set(z, (float)(0.0 > s ? 0.0 : s));
        } else if (f.strain[z] != 0.0f) {
            f.strain.set(z, 0.0f);
            Dictionary(f.edge_residual[z]).clear();
        }
    }
    // Load share, for "which edge": every live edge incident to a pushed vertex
    // banks the drive in proportion to how squarely the push runs along it.
    if (unresolved > 0.0) {
        const Array contacts = f.contact_particles.keys();
        for (int64_t ci = 0; ci < contacts.size(); ci++) {
            const Variant key = contacts[ci];
            const int64_t i = key;
            const int64_t z = f.contact_particles[key];
            const Vector2 normal = f.contact_normals[key];
            const int64_t from = f.incident_offsets[i];
            const int64_t to = f.incident_offsets[i + 1];
            for (int64_t k = from; k < to; k++) {
                const int64_t e_idx = f.incident_edges[k];
                const int32_t ex = f.edges[e_idx * 2 + 0];
                const int32_t ey = f.edges[e_idx * 2 + 1];
                const int64_t other = (int64_t)ex == i ? (int64_t)ey : (int64_t)ex;
                const Vector2 dir = positions[other] - positions[i];
                const double len = (double)dir.length();
                if (len <= 1e-6) {
                    continue;
                }
                const double along = (double)normal.dot(dir / (real_t)len);
                field_bank_load(f, z, e_idx, unresolved * (along < 0.0 ? -along : along));
            }
        }
        const Array contact_edges = f.contact_edges.keys();
        for (int64_t ei = 0; ei < contact_edges.size(); ei++) {
            const Variant key = contact_edges[ei];
            field_bank_load(f, (int64_t)f.contact_edges[key], (int64_t)key, unresolved);
        }
    }
    // Armed once, ascending zone, and held until GDScript's consume_break().
    if (f.break_edge < 0) {
        for (int64_t z = 0; z < zn; z++) {
            if ((double)f.strain[z] < f.shatter_distance) {
                continue;
            }
            const int64_t e = field_pick_edge(f, z);
            if (e >= 0) {
                f.break_edge = e;
                f.break_step = f.current_step;
                f.break_zone = z;
                break;
            }
        }
    }
    field_roll_driven(f, positions);
}

// BladeSwingClock.capture(), as a Dictionary GDScript turns back into a Bank.
Dictionary capture_clock(const FieldCtx &f) {
    Dictionary b;
    b["f"] = f.clock_f;
    b["drag"] = f.clock_drag;
    b["touched"] = f.clock_touched.duplicate();
    b["warping"] = f.clock_warping;
    b["last_t"] = f.clock_last_t;
    b["stalled"] = f.clock_stalled;
    return b;
}

// BladeObstacleField.capture(), likewise. Every packed array is an explicit
// fresh copy, never the live buffer.
Dictionary capture_field(const FieldCtx &f) {
    Dictionary b;
    b["strain"] = f.strain.duplicate();
    Array residual;
    for (int64_t z = 0; z < f.edge_residual.size(); z++) {
        residual.push_back(Dictionary(f.edge_residual[z]).duplicate());
    }
    b["edge_residual"] = residual;
    b["driven_last"] = f.driven_last.duplicate();
    b["driven_last_target"] = f.driven_last_target.duplicate();
    b["break_edge"] = f.break_edge;
    b["break_step"] = f.break_step;
    b["break_zone"] = f.break_zone;
    b["current_step"] = f.current_step;
    return b;
}

} // namespace

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
    ClassDB::bind_method(
            D_METHOD("simulate_range",
                    "positions", "prev_positions", "inv_masses",
                    "constraint_ab", "constraint_scalars",
                    "driver_particles", "driver_centers", "driver_scalars",
                    "damping", "step_offset", "step_count",
                    "dt", "base_iterations", "velocity_iter_ref",
                    "substeps", "length_factor"),
            &BladeSolverNative::simulate_range);
    ClassDB::bind_method(
            D_METHOD("simulate_range_field",
                    "positions", "prev_positions", "inv_masses",
                    "constraint_ab", "constraint_scalars",
                    "driver_particles", "driver_centers", "driver_scalars",
                    "damping", "step_offset", "step_count",
                    "dt", "base_iterations", "velocity_iter_ref",
                    "substeps", "length_factor", "field", "sim"),
            &BladeSolverNative::simulate_range_field);
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
    // BladeSim.simulate's `int(ceil(duration / dt))`, and its
    // `state.prev_positions = positions.duplicate()` at step 0: the history is
    // at rest, so `prev` IS `positions`.
    const int64_t steps = (int64_t)Math::ceil(p_duration / p_dt);
    return simulate_range(
            p_positions, p_positions, p_inv_masses,
            p_constraint_ab, p_constraint_scalars,
            p_driver_particles, p_driver_centers, p_driver_scalars,
            PackedFloat32Array(), 0, steps,
            p_dt, p_base_iterations, p_velocity_iter_ref,
            p_substeps, p_length_factor);
}

// THE stepping loop, and the only one. `p_fld` is null for a swing with neither
// a clock nor a defender field — the shape #798 shipped — and every hook below
// then compiles away to one null test per substep. A second loop for the
// defender case would be two definitions of the integrator, which is exactly
// what the parity contract cannot afford.
static Dictionary run_range(
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
        FieldCtx *p_fld) {
    const int64_t n = p_positions.size();
    const int64_t constraint_count = p_constraint_ab.size() / 2;
    const int64_t driver_count = p_driver_particles.size();
    // GDScript would index-error on the same inputs; fail as loudly.
    ERR_FAIL_COND_V_MSG(p_prev_positions.size() != n, Dictionary(),
            "prev_positions must parallel positions (a continued chunk needs the Verlet history it left).");
    ERR_FAIL_COND_V_MSG(p_inv_masses.size() != n, Dictionary(),
            "inv_masses must parallel positions.");
    ERR_FAIL_COND_V_MSG(p_damping.size() != 0 && p_damping.size() != n, Dictionary(),
            "damping must be empty or parallel positions.");

    // Working buffers, both copies of the caller's arrays. `prev` is taken AS
    // GIVEN — resetting it to `positions` is the caller's decision (step 0),
    // never this loop's; that is what makes a continued chunk possible.
    PackedVector2Array positions_buf = p_positions;
    PackedVector2Array prev_buf = p_prev_positions;
    Vector2 *positions = positions_buf.ptrw();
    Vector2 *prev = prev_buf.ptrw();

    // Per-particle, per-substep velocity retention (#801/#803). An EMPTY array
    // — every ordinary swing — skips the multiply outright, exactly as
    // BladeSim._step's `has_damping` does, so the undamped path is untouched
    // by this knob's existence.
    const bool has_damping = p_damping.size() > 0;
    const float *damping = has_damping ? p_damping.ptr() : nullptr;

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
    // samples[0] is the pose BEFORE any solver step of THIS chunk (#633).
    samples.push_back(snap);

    // prev_samples[k] parallels samples[k]: the Verlet history as it stands at
    // that sample (#803). [0] is the history on entry. Fresh copies, for the
    // same aliasing reason as `samples`.
    TypedArray<PackedVector2Array> prev_samples;
    PackedVector2Array prev_snap;
    prev_snap.resize(n);
    memcpy(prev_snap.ptrw(), p_prev_positions.ptr(), (size_t)n * sizeof(Vector2));
    prev_samples.push_back(prev_snap);

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

    // GDScript's `for local_step in step_count` runs zero times on a negative
    // count rather than erroring; match it.
    const int64_t steps = p_step_count > 0 ? p_step_count : 0;
    // BladeSim.simulate_range's `var sub := maxi(substeps, 1)`.
    const int64_t sub = p_substeps > 1 ? p_substeps : 1;
    const double sub_dt = p_dt / (double)sub;
    const double sub_dt_sq = sub_dt * sub_dt;

    for (int64_t step = 0; step < steps; step++) {
        // The INTEGER global step index — added as integers, THEN widened —
        // never an accumulated float offset (#803's trap).
        const double t0 = (double)(p_step_offset + step) * p_dt;
        // BladeObstacleField.begin_sample(): the GLOBAL index of the sample the
        // next substeps produce, which is what an armed break is stamped with.
        if (p_fld != nullptr && p_fld->has_field) {
            p_fld->current_step = p_step_offset + step + 1;
        }

        for (int64_t s = 0; s < sub; s++) {
            const double t = t0 + (double)(s + 1) * sub_dt;
            memset(speeds, 0, (size_t)n * sizeof(float));

            // --- Verlet integrate dynamic particles; track max speed. ---
            double max_speed_sq = 0.0;
            for (int64_t i = 0; i < n; i++) {
                if ((double)inv_masses[i] > 0.0) {
                    const Vector2 p = positions[i];
                    Vector2 v = p - prev[i];
                    if (has_damping) {
                        // `v *= maxf(0.0, 1.0 - float(damping[i]) * dt)` — the
                        // retention is a double expression, narrowed to real_t
                        // ONCE at the Vector2 multiply. Applied BEFORE the speed
                        // below, so speed_history sees the damped velocity, as
                        // GDScript's does. A zero entry yields exactly 1.0, and
                        // `v * 1.0f` is `v` bit for bit.
                        const double retention = 1.0 - (double)damping[i] * sub_dt;
                        v = v * (real_t)(retention > 0.0 ? retention : 0.0);
                    }
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

            // --- Open the substep on the swing clock BEFORE the drivers read
            // it, so a warping clock hands them THIS substep's advanced
            // progress (#780). Once per substep, never once per driver: they
            // all describe one rigid body turning about one pivot, and N ticks
            // would advance `_f` N times. ---
            const bool clocked = p_fld != nullptr && p_fld->has_clock;
            if (clocked) {
                clock_tick(*p_fld, t, sub_dt);
            }
            // BladeArcDriver._progress()'s shared half: -1.0 before the blade's
            // first contact, which leaves every driver below on its ORIGINAL
            // `t / duration` expression, character for character.
            const double warped = clocked ? clock_progress(*p_fld) : -1.0;

            // --- Drivers override prescribed particles (BladeArcDriver.apply). ---
            for (int64_t d = 0; d < driver_count; d++) {
                const double radius = ds[d * DRIVER_STRIDE + 0];
                const double start_angle = ds[d * DRIVER_STRIDE + 1];
                const double sweep = ds[d * DRIVER_STRIDE + 2];
                const double duration = ds[d * DRIVER_STRIDE + 3];
                const double f = warped >= 0.0
                        ? warped
                        : (duration > 0.0 ? Math::clamp(t / duration, 0.0, 1.0) : 0.0);
                // _sine_in_out — the one deliberate transcendental (#547).
                const double eased = 0.5 - 0.5 * Math::cos(Math::PI * f);
                const double angle = start_angle + sweep * eased;
                const Vector2 unit((real_t)Math::cos((real_t)angle), (real_t)Math::sin((real_t)angle));
                positions[dp[d]] = dc[d] + unit * (real_t)radius;
            }

            // Snapshot where the drivers PRESCRIBED the grip particles, before
            // the projection pass moves them to where the blade CAN be — the
            // two halves of the driver residual the strain meter reads.
            if (p_fld != nullptr && p_fld->has_field) {
                field_after_drivers(*p_fld, positions);
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
                // The defender field goes LAST in every iteration so the pass
                // ends outside every plate — that ordering is what makes
                // SHATTER_DISTANCE a visual penetration budget too.
                if (p_fld != nullptr && p_fld->has_field) {
                    field_project(*p_fld, positions, inv_masses, n);
                }
            }

            if (p_fld != nullptr && p_fld->has_field) {
                field_end_substep(*p_fld, positions);
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

        PackedVector2Array prev_step_snap;
        prev_step_snap.resize(n);
        memcpy(prev_step_snap.ptrw(), prev, (size_t)n * sizeof(Vector2));
        prev_samples.push_back(prev_step_snap);

        // The clock and the field bank per SAMPLE, parallel to `samples`, for
        // the resolve loop's rewind (#801/#803). GDScript owns entry [0] — it
        // captures before this call — so these are [1..step_count].
        if (p_fld != nullptr) {
            if (p_fld->has_clock) {
                p_fld->clock_history.push_back(capture_clock(*p_fld));
            }
            if (p_fld->has_field) {
                p_fld->field_history.push_back(capture_field(*p_fld));
            }
        }
    }

    // The caller writes these straight back onto its BladeState, so
    // simulate()'s in-place mutation contract survives the round trip.
    Dictionary out;
    out["samples"] = samples;
    out["prev_samples"] = prev_samples;
    out["speed_history"] = speed_history;
    out["positions"] = positions_buf;
    out["prev_positions"] = prev_buf;
    return out;
}

Dictionary BladeSolverNative::simulate_range(
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
        double p_length_factor) const {
    return run_range(
            p_positions, p_prev_positions, p_inv_masses,
            p_constraint_ab, p_constraint_scalars,
            p_driver_particles, p_driver_centers, p_driver_scalars,
            p_damping, p_step_offset, p_step_count,
            p_dt, p_base_iterations, p_velocity_iter_ref,
            p_substeps, p_length_factor, nullptr);
}

// Every key this reads is REQUIRED. A missing one would otherwise arrive as a
// default-constructed Variant and run a silently different physics — #779's
// `speed_history` lesson, applied to a boundary with twenty-odd values on it.
#define BLADE_REQUIRE_KEY(dict, key)                                                     \
    ERR_FAIL_COND_V_MSG(!(dict).has(key), Dictionary(),                                  \
            "simulate_range_field: missing '" key "' — the GDScript and native halves " \
            "of the defender boundary have drifted (see BladeObstacleField.native_inputs).")

Dictionary BladeSolverNative::simulate_range_field(
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
        const Dictionary &p_sim) const {
    BLADE_REQUIRE_KEY(p_field, "has_field");
    BLADE_REQUIRE_KEY(p_field, "has_clock");

    FieldCtx ctx;
    ctx.has_field = p_field["has_field"];
    ctx.has_clock = p_field["has_clock"];

    // Held as locals for the whole call: every `ptr()` below points into them.
    PackedVector2Array zone_centers;
    PackedFloat32Array zone_radii;
    PackedFloat32Array zone_drags;
    PackedByteArray zone_deflects;
    PackedInt32Array edges;
    PackedByteArray edge_removed;
    PackedFloat32Array vertex_radii;
    PackedInt32Array driven;
    PackedInt32Array incident_offsets;
    PackedInt32Array incident_edges;

    if (ctx.has_clock) {
        BLADE_REQUIRE_KEY(p_field, "clock_duration");
        BLADE_REQUIRE_KEY(p_sim, "clock_state");
        ctx.clock_duration = p_field["clock_duration"];
        const Dictionary clock_state = p_sim["clock_state"];
        BLADE_REQUIRE_KEY(clock_state, "f");
        BLADE_REQUIRE_KEY(clock_state, "drag");
        BLADE_REQUIRE_KEY(clock_state, "touched");
        BLADE_REQUIRE_KEY(clock_state, "warping");
        BLADE_REQUIRE_KEY(clock_state, "last_t");
        BLADE_REQUIRE_KEY(clock_state, "stalled");
        ctx.clock_f = clock_state["f"];
        ctx.clock_drag = clock_state["drag"];
        ctx.clock_touched = Dictionary(clock_state["touched"]).duplicate();
        ctx.clock_warping = clock_state["warping"];
        ctx.clock_last_t = clock_state["last_t"];
        ctx.clock_stalled = clock_state["stalled"];
    }

    if (ctx.has_field) {
        for (const char *key : { "zone_centers", "zone_radii", "zone_drags", "zone_deflects",
                     "edges", "edge_removed", "vertex_radii", "driven",
                     "incident_offsets", "incident_edges", "contact_slop",
                     "contact_hysteresis", "shatter_distance", "edge_radius" }) {
            ERR_FAIL_COND_V_MSG(!p_field.has(String(key)), Dictionary(),
                    String("simulate_range_field: missing field input '") + key + "'.");
        }
        BLADE_REQUIRE_KEY(p_sim, "field_state");

        zone_centers = p_field["zone_centers"];
        zone_radii = p_field["zone_radii"];
        zone_drags = p_field["zone_drags"];
        zone_deflects = p_field["zone_deflects"];
        edges = p_field["edges"];
        edge_removed = p_field["edge_removed"];
        vertex_radii = p_field["vertex_radii"];
        driven = p_field["driven"];
        incident_offsets = p_field["incident_offsets"];
        incident_edges = p_field["incident_edges"];

        ctx.zone_count = zone_radii.size();
        ERR_FAIL_COND_V_MSG(zone_centers.size() != ctx.zone_count
                        || zone_drags.size() != ctx.zone_count
                        || zone_deflects.size() != ctx.zone_count,
                Dictionary(), "simulate_range_field: the four zone arrays must be parallel.");
        ctx.edge_count = edges.size() / 2;
        ERR_FAIL_COND_V_MSG(edge_removed.size() != ctx.edge_count, Dictionary(),
                "simulate_range_field: edge_removed must have one byte per edge.");
        // The GDScript capsule pass indexes `radii[e.x]` unguarded, so a short
        // array is an index error there and would be a read past the end here.
        ERR_FAIL_COND_V_MSG(vertex_radii.size() != p_positions.size(), Dictionary(),
                "simulate_range_field: vertex_radii must parallel positions.");
        ERR_FAIL_COND_V_MSG(incident_offsets.size() != p_positions.size() + 1, Dictionary(),
                "simulate_range_field: incident_offsets must be one longer than positions.");

        ctx.zone_centers = zone_centers.ptr();
        ctx.zone_radii = zone_radii.ptr();
        ctx.zone_drags = zone_drags.ptr();
        ctx.zone_deflects = zone_deflects.ptr();
        ctx.edges = edges.ptr();
        ctx.edge_removed = edge_removed.ptr();
        ctx.vertex_radii = vertex_radii.ptr();
        ctx.vertex_radii_count = vertex_radii.size();
        ctx.driven = driven.ptr();
        ctx.driven_count = driven.size();
        ctx.incident_offsets = incident_offsets.ptr();
        ctx.incident_edges = incident_edges.ptr();
        ctx.contact_slop = p_field["contact_slop"];
        ctx.contact_hysteresis = p_field["contact_hysteresis"];
        ctx.shatter_distance = p_field["shatter_distance"];
        ctx.edge_radius = p_field["edge_radius"];

        // `_driven_set`, rebuilt from the same array `prepare()` deduplicated
        // into — one definition of "which particles a driver prescribes".
        for (int64_t k = 0; k < ctx.driven_count; k++) {
            ctx.driven_set[(int64_t)ctx.driven[k]] = true;
        }
        ctx.driven_targets.resize(ctx.driven_count);

        const Dictionary field_state = p_sim["field_state"];
        for (const char *key : { "strain", "edge_residual", "driven_last",
                     "driven_last_target", "break_edge", "break_step",
                     "break_zone", "current_step" }) {
            ERR_FAIL_COND_V_MSG(!field_state.has(String(key)), Dictionary(),
                    String("simulate_range_field: missing field_state '") + key + "'.");
        }
        ctx.strain = PackedFloat32Array(field_state["strain"]).duplicate();
        const Array residual_in = field_state["edge_residual"];
        for (int64_t z = 0; z < residual_in.size(); z++) {
            ctx.edge_residual.push_back(Dictionary(residual_in[z]).duplicate());
        }
        ERR_FAIL_COND_V_MSG(ctx.strain.size() != ctx.zone_count
                        || ctx.edge_residual.size() != ctx.zone_count,
                Dictionary(), "simulate_range_field: the accumulators must parallel the zones.");
        ctx.driven_last = PackedVector2Array(field_state["driven_last"]).duplicate();
        ctx.driven_last_target = PackedVector2Array(field_state["driven_last_target"]).duplicate();
        ctx.break_edge = field_state["break_edge"];
        ctx.break_step = field_state["break_step"];
        ctx.break_zone = field_state["break_zone"];
        ctx.current_step = field_state["current_step"];
    }

    Dictionary out = run_range(
            p_positions, p_prev_positions, p_inv_masses,
            p_constraint_ab, p_constraint_scalars,
            p_driver_particles, p_driver_centers, p_driver_scalars,
            p_damping, p_step_offset, p_step_count,
            p_dt, p_base_iterations, p_velocity_iter_ref,
            p_substeps, p_length_factor, &ctx);
    if (out.is_empty()) {
        return out; // run_range already errored
    }
    if (ctx.has_clock) {
        out["clock_state"] = capture_clock(ctx);
        out["clock_history"] = ctx.clock_history;
    }
    if (ctx.has_field) {
        out["field_state"] = capture_field(ctx);
        out["field_history"] = ctx.field_history;
    }
    return out;
}

#undef BLADE_REQUIRE_KEY
