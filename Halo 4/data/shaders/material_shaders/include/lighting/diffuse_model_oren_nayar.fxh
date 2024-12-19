#if !defined(__LIGHTING_DIFFUSE_MODEL_OREN_NAYAR_FXH)
#define __LIGHTING_DIFFUSE_MODEL_OREN_NAYAR_FXH

#include "core/core_types.fxh"
#include "lighting/vmf.fxh"
#include "lighting/sh.fxh"

////////////////////////////////////////////////////////////////////////////////
// Returns the N·L evaluation of the VMF
float3 VMFDiffuse_oren_nayar(
    const in s_vmf_sample_data vmfData,
    const in float3 normal,
	const in float3 geoNormal,
	const in float characterShadow,
	const in float floatingShadowAmount,
	const in int lightingMode,
    const in float3 shader_params)
{
	float3 diffuse;

	if (lightingMode == LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE || lightingMode == LM_PER_PIXEL_SIMPLE)
	{
		// Just transfer the irradiance
		diffuse = vmfData.coefficients[0].xyz;
	}
	else
	{
	#if defined(xenon) || (DX_VERSION == 11)
		const float directLightingMinimumForShadows = ps_bsp_lightmap_scale_constants.y;
	#else
		const float directLightingMinimumForShadows = 0.3f;
	#endif
		float shadowterm = saturate(characterShadow + directLightingMinimumForShadows);

		const bool allowSharpen = (lightingMode != LM_PROBE && lightingMode != LM_PROBE_AO && lightingMode != LM_PER_PIXEL_FORGE);
	
		// We now store two linear SH probes
		// [adamgold 2/13/12] now knock out direct with the character shadow (as long as we're not in the sun)
		diffuse = LinearSHEvaluate(vmfData, normal, geoNormal, 0, allowSharpen) * lerp(shadowterm, 1.0f, floatingShadowAmount)
				+ LinearSHEvaluate(vmfData, normal, geoNormal, 1, allowSharpen);
	}

	return diffuse;
}

////////////////////////////////////////////////////////////////////////////////
// oren nayar diffuse model (N�L)

void calc_diffuse_oren_nayar_initializer(
    inout float3 diffuse,
    const in s_common_shader_data common,
    const in float3 albedo,
    const in float3 shader_params,
    const in float3 normal,
    const in float3 metalness_color)
{
    diffuse = 0.0f;
    #if defined(xenon) || (DX_VERSION == 11)
        diffuse += VMFDiffuse_oren_nayar(
                    common.lighting_data.vmf_data,
                    common.normal,
                    common.geometricNormal,
                    common.lighting_data.shadow_mask.g,
                    common.lighting_data.savedAnalyticScalar,
                    common.lighting_mode,
                    shader_params);

        diffuse = CompSH(common, diffuse, normal) * shader_params.r;
#if defined(DEBUG)
        diffuse += ps_debug_ambient_intensity.xyz;
#endif
    #endif

}

void calc_diffuse_oren_nayar_inner_loop(
    inout float3 diffuse,
    const in s_common_shader_data common,
    const in float3 albedo,
    const in float3 shader_params, //ao, roughness, metalness
    const in float3 normal,
    const in float3 metalness_color,
    int index)
{
    float3 direction= common.lighting_data.light_direction_specular_scalar[index].xyz;
    float4 intensity_diffuse_scalar= common.lighting_data.light_intensity_diffuse_scalar[index];
        //TODO: test if inverting view_dir_distance.xyz is necessary. i do it in the main .fx so I may need to do so here as well.
        float LdotV = saturate(dot(direction, common.view_dir_distance.xyz));
        float NdotL = saturate(dot(direction, normal));
        float NdotV = saturate(dot(normal, common.view_dir_distance.xyz));

        float s = LdotV - NdotL * NdotV;
        float t = lerp(1.0, max(NdotL, NdotV), step(0.0, s));

        float sigma2 = shader_params.g * shader_params.g; //roughness * roughness
        float A = 1.0 + sigma2 * (albedo / (sigma2 + 0.13) + 0.5 / (sigma2 + 0.33));
        float B = 0.45 * sigma2 / (sigma2 + 0.09);

        //calculate fresnel schlick
        //float3 F = metalness_color + ((1-metalness_color) * pow(1-NdotV, 5));

        diffuse += max((max(0.0, NdotL) * (A + B * s / t) / 3.14159) * intensity_diffuse_scalar.rgb * intensity_diffuse_scalar.a, 0);// * (1.0 - F); did this break?
}

// build the loop
MAKE_ACCUMULATING_LOOP_4(float3, calc_diffuse_oren_nayar, float3, float3, float3, float3, MAX_LIGHTING_COMPONENTS);


#endif