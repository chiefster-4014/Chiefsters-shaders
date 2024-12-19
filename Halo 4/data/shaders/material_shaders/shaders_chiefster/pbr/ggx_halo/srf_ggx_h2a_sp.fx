/* ----------------------------------------------------------
srf_ggx_h2a_sp.fx
11/3/2024
a custom ggx material model.
by chiefster with help from chunch.
alternate version that tries to emulate H2ASP's wack shader.
very much still WIP.
---------------------------------------------------------- */
#include "core/core.fxh"
#include "engine/engine_parameters.fxh"
#include "lighting/lighting.fxh"
#include "lighting/specular_model_ggx.fxh"
#include "lighting/diffuse_model_oren_nayar.fxh"
#include "lighting/reflectionstuff.fxh"


DECLARE_SAMPLER(color_map, "Albedo Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER(specular_map, "Colored Specular Map", "", "shaders/default_bitmaps/bitmaps/default_spec.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER(normal_map, "Normal Map", "", "shaders/default_bitmaps/bitmaps/default_normal.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER_CUBE(reflection_map, "Reflection Map", "", "shaders/default_bitmaps/bitmaps/default_cube.tif")
#include "next_texture.fxh"

DECLARE_RGB_COLOR_WITH_DEFAULT(albedo_tint,	"", "", float3(1.0,1.0,1.0));
#include "used_float3.fxh"
DECLARE_FLOAT_WITH_DEFAULT(glossiness_scale,	"", "", 0, 1.0, float(1.0));
#include "used_float.fxh"
DECLARE_FLOAT_WITH_DEFAULT(glossiness_bias,		"", "", 0, 1.0, float(0.0));
#include "used_float.fxh"
DECLARE_FLOAT_WITH_DEFAULT(metalness_tint_r,		"", "", 0, 255.0, float(0.0));
#include "used_float.fxh"
DECLARE_RGB_COLOR_WITH_DEFAULT(metalness_tint_gba,	"", "", float3(1.0,1.0,1.0));
#include "used_float3.fxh"

DECLARE_BOOL_WITH_DEFAULT(detail_normals, "Detail Normals Enabled", "", false);
	#include "next_bool_parameter.fxh"
	DECLARE_SAMPLER(normal_detail_map, "Detail Normal Map", "detail_normals", "shaders/default_bitmaps/bitmaps/default_normal.tif");
	#include "next_texture.fxh"
	DECLARE_FLOAT_WITH_DEFAULT(detail_normal_intensity, "", "detail_normals", 0, 1.0, float(1.0));
	#include "used_float.fxh"
	#if defined(SELFILLUM)
		DECLARE_SAMPLER(selfillum_map, "Self-Illum Map", "", "shaders/default_bitmaps/bitmaps/color_white.bitmap")
		#include "next_texture.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(self_illum_color,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(self_illum_intensity, "", "", 0, 1.0, float(0.0));
		#include "used_float.fxh"
	#endif


struct s_shader_data
{
	s_common_shader_data common;
	float4 shader_params; // R - AO | G - Roughness | B - Metallic | A - fresnel mask (for cov stuff)
};

void pixel_pre_lighting(
		in s_pixel_shader_input pixel_shader_input,
		inout s_shader_data shader_data)
{
		float2 uv;
		uv = pixel_shader_input.texcoord.xy;

	shader_data.common.albedo = sample2DGamma(color_map, transform_texcoord(uv, color_map_transform));
	shader_data.common.albedo.rgb *= pow(albedo_tint, .454545);	//power to fix h4 color gamma correction

    shader_data.common.normal = sample_2d_normal_approx(normal_map, transform_texcoord(uv, normal_map_transform));
	shader_data.common.normal = mul(shader_data.common.normal, shader_data.common.tangent_frame);

	float4 pbr_masks = sample2DGamma(specular_map, transform_texcoord(uv, specular_map_transform));
	shader_data.shader_params = pbr_masks;
	shader_data.shader_params.a = (1-shader_data.shader_params.a) * glossiness_scale + glossiness_bias;

	{//normal mapping
		float3 base_normal = sample_2d_normal_approx(normal_map, transform_texcoord(uv, normal_map_transform));
		if (detail_normals) //taken from srf_blinn.fx
		{
			// Composite detail normal map onto the base normal map
			shader_data.common.normal = CompositeDetailNormalMap(base_normal,
																 normal_detail_map,
																 transform_texcoord(uv, normal_detail_map_transform),
																 detail_normal_intensity);
		}
		else
		{
			shader_data.common.normal = base_normal;
		}
		shader_data.common.normal = mul(shader_data.common.normal, shader_data.common.tangent_frame);
	}
}

float4 pixel_lighting(
        in s_pixel_shader_input pixel_shader_input,
	    inout s_shader_data shader_data)
{
    float3 normal = shader_data.common.normal;
	float4 albedo = shader_data.common.albedo;
	float3 view_dir = -shader_data.common.view_dir_distance.xyz;
	float4 shader_params = shader_data.shader_params;
	float3 diffuse = 0.0;
	float3 specular = 0.0;
	float NDV = 1.0f - saturate(dot((view_dir), normal));
	shader_params.rgb = max(shader_params.rgb, 0.04) * metalness_tint_gba + metalness_tint_r; /*the max() is a test so that the textures
																								don't always kill the specular if they
																								end up black due to compression, etc.*/
 /*------------------------------------SPECULAR CALCULATION------------------------------------*/
		//big thanks to the oomer for giving me an example on how to do these for loops!
	for (uint i = 0; i < shader_data.common.lighting_data.light_component_count; i++)
	{
		float4 light = shader_data.common.lighting_data.light_direction_specular_scalar[i];
		float3 color = shader_data.common.lighting_data.light_intensity_diffuse_scalar[i].rgb;

		//analytical lighting * light color * light intensity * f0
		specular = calc_specular_ggx_new(shader_params.a, normal, light.rgb, view_dir, shader_params.rgb) * color * light.a * max(dot(normal, light.rgb), 0);
	}
 /*-------------------------------IN-DIRECT SPECULAR CALCULATION-------------------------------*/
	if (shader_data.common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && shader_data.common.lighting_mode != LM_PER_PIXEL_SIMPLE)
	{
		for (uint i = 0; i < 2; i++)
		{
			float3 light = VMFGetVector(shader_data.common.lighting_data.vmf_data, i);

			//final analytical lighting + VMF specular (indrect) * f0
			specular += VMFSpecularCustomEvaluate3(shader_data.common.lighting_data.vmf_data,
			 calc_specular_ggx_new(shader_params.a, normal, light, view_dir, shader_params.rgb), i) * max(dot(normal, light), 0);
		}
	}
 /*------------------------------------------DIFFUSE------------------------------------------*/
	calc_diffuse_oren_nayar(diffuse, shader_data.common, albedo.rgb, (1 / sqrt(2)) * atan(shader_params.a), normal, shader_params.rgb);
 /*-----------------------------------------REFLECTION-----------------------------------------*/
	float3 reflection = 0.0;
 		//calculate reflection. roughness controls blurriness of cubemap. (won't look correct if cubemap only has a few mipmaps.)
	{
		float3 envmap_area_specular_only = 0.0;

    	calc_prebake_envtint(envmap_area_specular_only, shader_data.common, shader_data.common.normal, float2(0.45, 0.55), shader_params.rgb, 1.0, 5);
		float3 rVec				= reflect(-view_dir, normal);
		float lod				= float_remap(pow(shader_params.a, .454545), 0, 1, 0, 8); // Exponential for smoother mip progression. remap attempts to push into proper mip range for 256x cubes. 
		float4 reflectionMap	= sampleCUBELOD(reflection_map, rVec, lod);
		reflection				= envmap_area_specular_only * reflectionMap.rgb * reflectionMap.a * FresnelSchlickWithRoughness(shader_params.rgb, NDV, 1-shader_params.a);
	}
 /*----------------------------------------FINAL OUTPUT----------------------------------------*/
    float4 out_color;
	out_color.rgb = (diffuse * albedo.rgb) + specular + reflection;
	out_color.a = albedo.a;

 /*-----------------------------------------SELF-ILLUM-----------------------------------------*/
	#if defined(SELFILLUM)
		if (AllowSelfIllum(shader_data.common))
		{
			float3 self_illum = sample2DGamma(selfillum_map, transform_texcoord(pixel_shader_input.texcoord.xy, selfillum_map_transform));
			out_color.rgb += self_illum * self_illum_color * self_illum_intensity;
			shader_data.common.selfIllumIntensity = GetLinearColorIntensity(self_illum);
		}
	#endif
	return out_color;
}

#include "techniques.fxh"
