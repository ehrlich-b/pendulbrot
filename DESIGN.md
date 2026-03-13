# Pendulbrot: Design Document

## Vision

A zoomable fractal explorer for the double pendulum. Map initial conditions
onto a 2D plane, simulate each one, color by outcome. The key feature no
one has built: **deep zoom** into the fractal boundary to see if it's
self-similar, plus a resolution slider that transitions from visible animated
pendulums down to single-pixel coloring.

## Stack

**Single HTML file.** Vanilla JavaScript + WebGPU compute shaders (WGSL
inlined as template strings). No build step, no dependencies, no framework.
Open the file in Chrome/Edge/Firefox/Safari and it works.

Fallback: if WebGPU is unavailable, show an error message. We don't
polyfill to WebGL2 -- compute shaders are the whole point.

```
pendulbrot/
    index.html          -- everything: JS, WGSL shaders, CSS, UI
    DESIGN.md           -- this file
```

That's it.

## The Physics

### Model: Compound Double Pendulum

Two identical uniform rods (not point masses), each of mass `m` and length
`l`, connected by frictionless pivots. This is the same model used by both
Heyl (2008) and Reusser.

### State Vector

```
[theta1, theta2, p1, p2]
```

Where `theta1`, `theta2` are angles from vertical and `p1`, `p2` are
conjugate momenta.

### Equations of Motion (Hamiltonian form, non-dimensionalized: m=l=g=1)

From the Lagrangian (Heyl eq. 4, Reusser's GLSL):

```
L = (1/6) [theta2_dot^2 + 4*theta1_dot^2 + 3*theta1_dot*theta2_dot*cos(D)]
  + (1/2) [3*cos(theta1) + cos(theta2)]
```

where `D = theta1 - theta2`.

Conjugate momenta:

```
p1 = (1/6) [8*theta1_dot + 3*theta2_dot*cos(D)]
p2 = (1/6) [2*theta2_dot + 3*theta1_dot*cos(D)]
```

Inverted (angular velocities from momenta):

```
theta1_dot = 6 * [2*p1 - 3*cos(D)*p2] / [16 - 9*cos^2(D)]
theta2_dot = 6 * [8*p2 - 3*cos(D)*p1] / [16 - 9*cos^2(D)]
```

Momentum evolution:

```
p1_dot = -0.5 * [theta1_dot * theta2_dot * sin(D) + 3*sin(theta1)]
p2_dot = -0.5 * [-theta1_dot * theta2_dot * sin(D) + sin(theta2)]
```

Time unit = sqrt(l/g). Period of small oscillations ~ 7.7 time units.

### Energy Conservation

Initial energy (released from rest):

```
H0 = -(1/2) [3*cos(theta1) + cos(theta2)]
```

Flip is energetically impossible when:

```
3*cos(theta1) + cos(theta2) > 2
```

This defines the central "no-flip island" analytically.

### Integration

RK4 with fixed timestep. Default `dt = 0.03` (same as Reusser). The WGSL
compute shader runs N RK4 steps per dispatch, accumulating results across
frames.

### Reference WGSL (the core simulation kernel)

```wgsl
fn derivative(state: vec4f) -> vec4f {
    let theta = state.xy;
    let p = state.zw;
    let cosD = cos(theta.x - theta.y);
    let sinD = sin(theta.x - theta.y);
    let denom = 16.0 - 9.0 * cosD * cosD;

    let thetaDot = 6.0 * vec2f(
        2.0 * p.x - 3.0 * cosD * p.y,
        8.0 * p.y - 3.0 * cosD * p.x
    ) / denom;

    let pDot = -0.5 * vec2f(
        thetaDot.x * thetaDot.y * sinD + 3.0 * sin(theta.x),
        -thetaDot.x * thetaDot.y * sinD + sin(theta.y)
    );

    return vec4f(thetaDot, pDot);
}

fn rk4(state: vec4f, dt: f32) -> vec4f {
    let k1 = dt * derivative(state);
    let k2 = dt * derivative(state + 0.5 * k1);
    let k3 = dt * derivative(state + 0.5 * k2);
    let k4 = dt * derivative(state + k3);
    return state + (k1 + 2.0 * k2 + 2.0 * k3 + k4) / 6.0;
}
```

## What We're Visualizing

### The Domain: A 4D Phase Space

The initial conditions `(theta1, theta2, omega1, omega2)` form a 4D space.
Any image is a **2D slice** through this 4D space. Different slices reveal
different physics.

### Standard Slice: (theta1, theta2) at Rest

- X axis = theta1, Y axis = theta2, both in [-pi, pi]
- omega1 = omega2 = 0 (released from rest)
- This is what Heyl and Reusser both show
- Produces the classic "eye" shape with the no-flip island in the center

### The "View Rotation" Idea

The 2D slice is defined by:
- A **center point** in 4D: `(theta1_0, theta2_0, omega1_0, omega2_0)`
- Two **basis vectors** in 4D: `u` and `v` (the x and y axes of the image)

The standard slice uses center `(0, 0, 0, 0)`, `u = (1,0,0,0)`,
`v = (0,1,0,0)`. But we can **rotate** `u` and `v` continuously through 4D
space, producing a morphing fractal:

| Slice | u | v | What you see |
|-------|---|---|--------------|
| Standard | (1,0,0,0) | (0,1,0,0) | Config space fractal (classic) |
| Phase portrait arm 1 | (1,0,0,0) | (0,0,1,0) | theta1 vs omega1 |
| Phase portrait arm 2 | (0,1,0,0) | (0,0,0,1) | theta2 vs omega2 |
| Cross-phase | (1,0,0,0) | (0,0,0,1) | theta1 vs omega2 |
| Normal modes | (1,1,0,0)/sqrt2 | (1,-1,0,0)/sqrt2 | Sum/difference angles |
| Arbitrary | smooth interpolation | between any of the above | morphing fractal |

In the UI: a dropdown for preset slices + a slider for smooth interpolation
between presets. Full SO(4) rotation via shift+drag is a stretch goal.

### Torus Topology

Both angles are periodic, so the config space is a flat torus T^2. We could
optionally render the fractal ON a torus surface embedded in 3D, colored by
the outcome metric. This is a stretch goal.

### Energy-Constrained Slices (Poincare Sections)

Fix total energy `E` and distribute it between the arms. For each pixel,
solve for the initial velocities that give energy `E`. Sliding `E` morphs
the fractal continuously and reveals KAM island structure. Stretch goal.

## Coloring Modes

### Mode 1: Flip Time (Mandelbrot Analog) -- PRIMARY

Count time until either arm flips (|theta| crosses pi). Direct analog of
Mandelbrot escape time. Continuous coloring via log-scaled flip time through
a colormap. Pixels that never flip get a distinct "interior" color (black
or white).

### Mode 2: Final Angular Position (Reusser Style)

Color by `(theta1(T), theta2(T))` at end of simulation:

```
color = pow(0.5 + 0.5 * vec3(sin(u)*cos(v), sin(u)*sin(v), -cos(u)), 0.75)
```

Smooth, psychedelic mixing patterns.

### Mode 3: Flip Count

How many times does either arm flip within the simulation time? Integer
coloring with discrete level sets, like Mandelbrot exterior bands.

### Mode 4: Which Arm Flips First (Wada Basins)

Three outcomes: arm 1 first, arm 2 first, neither. Creates Wada basins --
boundaries where all three regions meet at every point. Stretch goal.

## The Resolution Slider

A single slider controls `cellSize` in pixels:

### cellSize >= 40px: Animated Pendulums

- Grid of visible animated double pendulums
- Each cell shows two line segments + two circle bobs
- Background colored by fractal metric
- Simulation runs forward in real time
- Rendered via a second compute pass that writes pendulum geometry into
  a vertex buffer, or more simply: draw pendulums with Canvas 2D overlay
  on top of the WebGPU canvas

### cellSize 2-39px: Colored Squares

- Too small for visible pendulums
- Each square colored by the fractal metric at its center

### cellSize = 1px: Full Fractal

- One pixel per initial condition
- Maximum resolution fractal rendering

Implementation: the compute shader always simulates a grid of
`ceil(canvasW / cellSize) * ceil(canvasH / cellSize)` pendulums. The render
shader maps each result onto a `cellSize x cellSize` block of pixels. At
cellSize=1, it's 1:1. At cellSize=80 on a 1600px canvas, it's ~400
pendulums total.

For the animated pendulum overlay at large cellSize: use a 2D canvas
layered on top. Each frame, read back the current simulation state for those
~400 pendulums and draw them with simple line+circle canvas calls. Reading
back ~400 * 4 floats per frame is trivially cheap.

## Zoom Architecture

### The Hard Problem

Unlike Mandelbrot, there's no closed-form shortcut. Every pixel requires
a full simulation from t=0 to t=T. This means:

- Zoom is expensive: recompute the entire image
- Deep zoom may hit f32 precision limits (~1e-7 scale)
- Simulation time T determines "depth" of the fractal

### Progressive Rendering

When the user zooms or pans:

1. **Frame 0**: Compute at 8x coarse grid (every 8th pixel). Instant.
2. **Frame 1**: Fill in 4x.
3. **Frame 2**: Fill in 2x.
4. **Frame 3**: Fill in 1x (full resolution).

Each frame only computes NEW pixels. The render shader stretches coarse
results to fill gaps until finer results arrive. User sees instant coarse
feedback that refines over ~4 frames.

### Incremental Simulation

The simulation doesn't run all at once. Each frame dispatches N RK4 steps
(e.g. 100 steps * dt=0.03 = 3 time units per frame). The fractal "develops"
over many frames as the simulation accumulates more time. This gives:

- Instant visual feedback (coarse structure appears in first few frames)
- Progressive refinement as longer simulations reveal finer features
- Naturally responsive -- user can zoom/pan anytime, restarting the sim

Total simulation budget: ~10,000 time units (~1300 oscillation periods).
At 100 steps/frame, that's ~3300 frames = ~55 seconds at 60fps to reach
full depth.

### Zoom-Dependent Simulation Time

At higher zoom, finer structure needs longer simulation:

```
T = T_base * (1 + log2(1 / zoom_scale))
```

Default T_base = 5000 time units at 1x zoom.

### Precision

f32 is all we have in WebGPU compute shaders. For the initial version,
accept this limitation. If the fractal is interesting enough at deep zoom
to warrant it, we can later emulate f64 with double-float (two f32s,
~48 bits mantissa, ~2x slower). But we should find out empirically whether
it matters first.

## GPU Architecture

### Buffers

```
stateBuffer:      array<vec4f>  -- [theta1, theta2, p1, p2] per pixel
metricsBuffer:    array<vec4f>  -- [flipTime, flipCount, finalTheta1, finalTheta2] per pixel
uniformBuffer:    struct        -- zoom center, zoom scale, cellSize, dt, simTime, colorMode, slice params
```

### Compute Pipeline

One compute shader, dispatched each frame:

```wgsl
@compute @workgroup_size(256)
fn simulate(@builtin(global_invocation_id) gid: vec3u) {
    let idx = gid.x;
    if (idx >= totalPixels) { return; }

    var state = stateBuffer[idx];
    var metrics = metricsBuffer[idx];

    // Run N RK4 steps
    for (var i = 0u; i < stepsPerFrame; i++) {
        state = rk4(state, dt);
        simTime += dt;

        // Check for flip
        if (abs(state.x) > PI || abs(state.y) > PI) {
            if (metrics.x == 0.0) { // first flip
                metrics.x = simTime;
            }
            metrics.y += 1.0; // flip count
            state.x = modAngle(state.x); // wrap back to [-pi, pi]
            state.y = modAngle(state.y);
        }
    }

    metrics.z = state.x; // final theta1
    metrics.w = state.y; // final theta2
    stateBuffer[idx] = state;
    metricsBuffer[idx] = metrics;
}
```

### Render Pipeline

Full-screen quad. Vertex shader generates two triangles covering the
viewport. Fragment shader reads from metricsBuffer and applies the selected
colormap:

```wgsl
@fragment
fn render(@builtin(position) pos: vec4f) -> @location(0) vec4f {
    let pixelCoord = vec2u(pos.xy);
    let gridCoord = pixelCoord / cellSize;
    let idx = gridCoord.y * gridWidth + gridCoord.x;
    let metrics = metricsBuffer[idx];

    // Apply colormap based on colorMode uniform
    switch (colorMode) {
        case 0: return flipTimeColor(metrics.x);
        case 1: return angularPositionColor(metrics.zw);
        case 2: return flipCountColor(metrics.y);
    }
}
```

### Initialization

On zoom/pan change or startup:

```wgsl
@compute @workgroup_size(256)
fn initialize(@builtin(global_invocation_id) gid: vec3u) {
    let idx = gid.x;
    let gridX = idx % gridWidth;
    let gridY = idx / gridWidth;

    // Map pixel to initial conditions via current slice
    let nx = (f32(gridX) / f32(gridWidth) - 0.5) * 2.0;  // [-1, 1]
    let ny = (f32(gridY) / f32(gridHeight) - 0.5) * 2.0;

    // Apply zoom: map to world coordinates
    let wx = zoomCenter.x + nx * zoomScale;
    let wy = zoomCenter.y + ny * zoomScale;

    // Apply 4D slice basis vectors
    let ic = sliceCenter + wx * sliceBasisU + wy * sliceBasisV;

    stateBuffer[idx] = ic;
    metricsBuffer[idx] = vec4f(0.0);
}
```

## UI (HTML/CSS)

Minimal overlay on the canvas. No framework -- just positioned divs.

### Controls

- **Resolution slider**: cellSize from 1 to 80px
- **Color mode dropdown**: Flip Time / Angular Position / Flip Count
- **Slice preset dropdown**: Standard / Phase Arm 1 / Phase Arm 2 /
  Cross-Phase / Normal Modes
- **Simulation speed**: steps per frame (10-500)
- **Simulation time display**: current accumulated sim time
- **Reset button**: restart simulation at current view

### Interaction

- **Scroll wheel**: zoom in/out centered on cursor
- **Click+drag**: pan
- **Double-click**: zoom in 2x at cursor

All zoom/pan actions reset the simulation (reinitialize buffers).

## Initialization Sequence

```
1. Request WebGPU adapter + device
2. Create canvas, configure context
3. Create buffers (state, metrics, uniforms)
4. Create compute pipelines (initialize, simulate)
5. Create render pipeline (fullscreen quad + colormap)
6. Run initialize compute pass
7. Start animation loop:
   a. Update uniforms (sim time, etc.)
   b. Dispatch simulate compute pass (N steps)
   c. Dispatch render pass
   d. If cellSize >= 40: draw pendulum overlay on 2D canvas
   e. requestAnimationFrame -> loop
```

## Key References

- **Heyl 2008** "The Double Pendulum Fractal" -- fat fractal measurement,
  flip-time coloring, 2^15 x 2^15 grid, quasi-self-similarity observation,
  boundary area mu(eps) = A*eps^beta + mu(0) where mu(0) ~ 0.057
- **Reusser (Observable)** -- GPU implementation (WebGL/regl), state-in-RGBA
  texture, final-position coloring, interactive zoom, GLSL derivative fn
- **tryabin/double-pendulum-fractal** -- CUDA implementation, Fehlberg 8(7)
  integrator, flip-time + neighbor-divergence coloring
- **Shinbrot et al. 1992** -- original double pendulum chaos analysis
- **Farmer 1985** -- fat fractal theory, scaling exponents

## Open Questions

1. **How deep does the self-similarity go?** Heyl shows two zoom levels
   with recognizable structure. Nobody has gone deeper. The fat fractal
   property (mu(0) > 0) means the boundary never fully resolves -- but
   does it stay *interesting*?

2. **Which coloring mode produces the best zoom experience?** Flip-time
   gives sharp boundaries (good for zoom). Final-position gives smooth
   mixing (pretty but maybe less zoom-worthy). Need to try both.

3. **Does the 4D slice rotation reveal genuinely new structures?** Or do
   all slices look qualitatively similar? The normal-mode slice
   `(theta1+theta2, theta1-theta2)` might be particularly interesting
   since it diagonalizes the linearized system.

4. **f32 precision ceiling**: At what zoom level does it become unusable?
   Is the fractal interesting enough at that scale to justify double-float
   emulation?
