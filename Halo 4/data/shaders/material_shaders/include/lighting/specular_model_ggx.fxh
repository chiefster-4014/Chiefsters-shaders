#if !defined(__LIGHTING_SPECULAR_MODEL_GGX_FXH)
#define __LIGHTING_SPECULAR_MODEL_GGX_FXH

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

////////////////////////////////////////////////////////////////////////////////
// PBR met-rough GGX specular model
// taken from my reach version because it worked well
float3 calc_specular_ggx(
        in float roughness,
        const in float3 normal,
        const in float3 light,
        const in float3 view_dir)
	{
        //##TODO: test if power of 2.2 is better for shading.
        roughness = clamp(pow(roughness, 2), 0.01, 1);      //roughness values of 0 breaks shading. clamp to .01 so nobody breaks it.

        //ggx specular calculation
        float NDL = saturate(dot(normal, light));
        float NDV = saturate(dot((view_dir), normal));
        float3 NDH = dot(normalize(light + view_dir), normal);
        float3 G1_VL = (NDL * 2) / (NDL+sqrt((pow(NDL,2)) * (1-pow(roughness,2))) + pow(roughness,2));
        float3 G2_VL = (NDV * 2) / (NDV+sqrt((pow(NDV,2)) * (1-pow(roughness,2))) + pow(roughness,2));
        float3 GGXNormalDistrubtion = pow(roughness,2) / (pow((pow(NDH, 2) * (pow(roughness, 2) - 1)) + 1, 2) * 3.141592658);
        //finalized ggx specular
        return GGXNormalDistrubtion * G1_VL * G2_VL;
	}
#endif