#if !defined(__LIGHTING_DIFFUSE_MODEL_OREN_NAYAR_FXH)
#define __LIGHTING_DIFFUSE_MODEL_OREN_NAYAR_FXH

#include "core/core_types.fxh"
#include "lighting/vmf.fxh"
#include "lighting/sh.fxh"



////////////////////////////////////////////////////////////////////////////////
// oren nayar diffuse model (N�L)

void calc_diffuse_oren_nayar_initializer(
    inout float3 diffuse,
    const in s_common_shader_data common,
    const in float3 albedo,
    const in float roughness,
    const in float3 normal)
{
    diffuse = 0.0f;
    #if defined(xenon) || (DX_VERSION == 11)
        diffuse += VMFDiffuse(common.lighting_data.vmf_data, common.normal, common.geometricNormal, common.lighting_data.shadow_mask.g, common.lighting_data.savedAnalyticScalar, common.lighting_mode);
        diffuse = CompSH(common, diffuse, normal);
#if defined(DEBUG)
        diffuse += ps_debug_ambient_intensity.xyz;
#endif
    #endif

}

void calc_diffuse_oren_nayar_inner_loop(
    inout float3 diffuse,
    const in s_common_shader_data common,
    const in float3 albedo,
    const in float roughness,
    const in float3 normal,
    int index)
{
    float3 direction= common.lighting_data.light_direction_specular_scalar[index].xyz;
    float4 intensity_diffuse_scalar= common.lighting_data.light_intensity_diffuse_scalar[index];

        float LdotV = dot(direction, common.view_dir_distance.xyz);
        float NdotL = dot(direction, normal);
        float NdotV = dot(normal, common.view_dir_distance.xyz);

        float s = LdotV - NdotL * NdotV;
        float t = lerp(1.0, max(NdotL, NdotV), step(0.0, s));

        float sigma2 = roughness * roughness;
        float A = 1.0 + sigma2 * (albedo / (sigma2 + 0.13) + 0.5 / (sigma2 + 0.33));
        float B = 0.45 * sigma2 / (sigma2 + 0.09);

        diffuse += max((max(0.0, NdotL) * (A + B * s / t) / 3.14159) * intensity_diffuse_scalar.rgb * intensity_diffuse_scalar.a, 0);
}

// build the loop
MAKE_ACCUMULATING_LOOP_3(float3, calc_diffuse_oren_nayar, float3, float, float3, MAX_LIGHTING_COMPONENTS);


#endif