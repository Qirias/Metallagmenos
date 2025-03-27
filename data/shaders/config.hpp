// When enabled, writes depth values in eye space to the g-buffer depth
// component. This allows the deferred pass to calculate the eye space fragment
// position more easily in order to apply lighting.  When disabled, the screen
// depth is written to the g-buffer depth component and an extra inverse
// transform from screen space to eye space is necessary to calculate lighting
// contributions in the deferred pass.
//#define USE_EYE_DEPTH              1
#define USE_REVERSE_Z              1

// When enabled, uses the stencil buffer to avoid execution of lighting
// calculations on fragments that do not intersect with a 3D light volume.
// When disabled, all fragments covered by a light in screen space will have
// lighting calculations executed. This means that considerably more fragments
// will have expensive lighting calculations executed than is actually
// necessary.
#define LIGHT_STENCIL_CULLING      1
