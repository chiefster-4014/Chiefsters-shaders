#if !defined(__SPECULAR_MODEL_GGX_FXH)
#define __SPECULAR_MODEL_GGX_FXH

//needed for shader calc
#include "core/core_types.fxh"
#include "lighting/vmf.fxh"

//added for VMF
#include "core/core.fxh"
#include "lighting/sh.fxh"

float3 FresnelSchlickWithRoughness(float3 SpecularColor, float NdotV, float Gloss) //taken from H2AMP specular_models.fxh
{
    return SpecularColor + (max(Gloss, SpecularColor) - SpecularColor) * pow(1-NdotV, 5);
}

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
//metalness was originally handled here, but is now handled in the .fx file.
float3 calc_specular_ggx(
        const in float roughness,
        const in float3 normal,
        const in float3 light_dir,
        const in float3 view_dir)
	{
        float roughness4 = clamp(roughness, 0.075, 1);       //roughness values of 0 breaks shading. clamp to .0001 so nobody breaks it.
        roughness4 = roughness4 * roughness4 * roughness4 * roughness4;
        //ggx specular calculation
        float NDL = saturate(dot(normal, light_dir));
        float NDV = saturate(dot((view_dir), normal));
        float3 NDH = dot(normalize(light_dir + view_dir), normal);
        float3 G1_VL = (NDL * 2) / (NDL+sqrt((pow(NDL,2)) * (1-roughness4) + roughness4));
        float3 G2_VL = (NDV * 2) / (NDV+sqrt((pow(NDV,2)) * (1-roughness4) + roughness4));
        float3 GGXNormalDistrubtion = roughness4 / (pow((pow(NDH, 2) * (roughness4 - 1)) + 1, 2) * 3.14159);
        //finalized ggx specular
        return GGXNormalDistrubtion * G1_VL * G2_VL;
	}

float3 calc_specular_ggx_new(
    const in float3 shader_params,
    const in float3 normal,
    const in float3 light_dir,
    const in float3 view_dir,
    const in float3 f0) 
    {
        //define cool stuff i need
        float roughness4 = clamp(shader_params.g, 0.05, 1);       //roughness values of 0 breaks shading. clamp so nobody breaks it.
        roughness4 = roughness4 * roughness4 * roughness4 * roughness4;

        //OLI'S COMMENT: Set these dot-products to return 0 if they go into the negatives.
        float NDL = saturate(dot(normal, light_dir));
        float NDV = saturate(dot(view_dir, normal));
        float NDH = saturate(dot(normalize(light_dir + view_dir), normal));
        //float LDH = saturate(dot(normalize(light_dir + view_dir), light_dir));


        //calculate GGX normal distribution
        float d = ((NDH * roughness4 - NDH) * NDH + 1);
        float D = roughness4 / (d * d * pi);
        

        //calculate schlick masking term
        //float G1_VL = NDV / (NDV * (1 - roughness4) + roughness4);
        //float G2_VL = NDL / (NDL * (1 - roughness4) + roughness4);
        float3 G1_VL = (NDL * 2) / (NDL+sqrt((pow(NDL,2)) * (1-roughness4) + roughness4));
        float3 G2_VL = (NDV * 2) / (NDV+sqrt((pow(NDV,2)) * (1-roughness4) + roughness4));
        float G = G1_VL * G2_VL;


        //calculate fresnel schlick. using H2AMP's function as it gives better results than standard schlick.
        float3 F = FresnelSchlickWithRoughness(f0, NDV, 1-shader_params.g);


        //calculate GGX term.       OLI'S COMMENT: Added the denominator back as it should not break specular at all and is necessary for this to actually be PBR.
        float3 GGXTerm = (D * G * F) / max(4.0 * NDV * NDL, _epsilon);
        return GGXTerm;
    }
#endif