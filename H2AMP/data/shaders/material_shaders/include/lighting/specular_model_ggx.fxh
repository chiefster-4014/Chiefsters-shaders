#if !defined(__SPECULAR_MODEL_GGX_FXH)
#define __SPECULAR_MODEL_GGX_FXH

//needed for shader calc
#include "core/core_types.fxh"
#include "lighting/vmf.fxh"

//added for VMF
#include "core/core.fxh"
#include "lighting/sh.fxh"



float3 VMFSpecularCustomEvaluate3(
    const in s_vmf_sample_data vmfData,
    const in float3 innerProduct,
    const in int vmfIndex)
{
    float3 vmfIntensity = max(0.0, innerProduct);
    return vmfData.coefficients[vmfIndex * 2 + 1].rgb * vmfIntensity;
}

float3 get_fresnel_shlick(
const in float3 metalness_color,
    const in float3 normal,
    const in float3 view_dir)
    {
        return metalness_color + ((1-metalness_color) * pow(1-dot(normalize(view_dir), normal), 5));
    }

////////////////////////////////////////////////////////////////////////////////
// GGX lighting model
float3 calc_specular_ggx(
        const in float roughness,
        const in float3 normal,
        const in float3 light_dir,
        const in float3 view_dir)
	{
        float roughness4 = clamp(roughness, 0.075, 1);       //roughness values of 0 breaks shading. clamp here so nobody breaks it.
        roughness4 = roughness4 * roughness4 * roughness4 * roughness4;
        //ggx specular calculation
        float NDL = saturate(dot(normal, light_dir));
        float NDV = saturate(dot((view_dir), normal));
        float3 NDH = dot(normalize(light_dir + view_dir), normal);
        float3 G1_VL = (NDL * 2) / (NDL+sqrt((pow(NDL,2)) * (1-roughness4)) + roughness4);
        float3 G2_VL = (NDV * 2) / (NDV+sqrt((pow(NDV,2)) * (1-roughness4)) + roughness4);
        float3 GGXNormalDistrubtion = roughness4 / (pow((pow(NDH, 2) * (roughness4 - 1)) + 1, 2) * 3.14159);
        //finalized ggx specular
        return GGXNormalDistrubtion * G1_VL * G2_VL;
	}
#endif