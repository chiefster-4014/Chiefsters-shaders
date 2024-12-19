/* ----------------------------------------------------------
srf_ggx_h2a_mp.fx
7/4/2024 - chiefster with help from chunch.
a custom ggx material model.
swaps pbr mask channels with h2a mp channels.
---------------------------------------------------------- */

#include "core/core.fxh"
#include "engine/engine_parameters.fxh"
#include "lighting/lighting.fxh"
#include "lighting/specular_model_ggx.fxh"
#include "lighting/diffuse_model_oren_nayar.fxh"
#include "lighting/reflectionstuff.fxh"


DECLARE_SAMPLER(color_map, "Albedo Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER(combo_map, "Combo Map", "", "shaders/default_bitmaps/bitmaps/color_white.bitmap")
#include "next_texture.fxh"


#if defined(CHANGE_COLOR) //same stuff from srf_pbr_spartan
	DECLARE_SAMPLER(tint_map, "Tint Map", "Tint Map", "shaders/default_bitmaps/bitmaps/color_white.tif");
	#include "next_texture.fxh"
	DECLARE_RGB_COLOR_WITH_DEFAULT(base_color,	"Base Color", "", float3(1,1,1));
	#include "used_float3.fxh"
	// Diffuse Primary and Secondary Change Colors
	#if defined(cgfx) || defined(ARMOR_PREVIS)
		DECLARE_RGB_COLOR_WITH_DEFAULT(tmp_primary_cc,	"Test Primary Color", "", float3(1,1,1));
		#include "used_float3.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(tmp_secondary_cc,	"Test Secondary Color", "", float3(1,1,1));
		#include "used_float3.fxh"
	#endif
#endif

DECLARE_SAMPLER(normal_map, "Normal Map", "", "shaders/default_bitmaps/bitmaps/default_normal.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER_CUBE(reflection_map, "Reflection Map", "", "shaders/default_bitmaps/bitmaps/default_cube.tif")
#include "next_texture.fxh"

DECLARE_RGB_COLOR_WITH_DEFAULT(albedo_tint, "", "", float3(1.0,1.0,1.0));
#include "used_float3.fxh"
DECLARE_FLOAT_WITH_DEFAULT(roughness_scalar, "", "", 0, 1.0, float(1.0));
#include "used_float.fxh"
DECLARE_FLOAT_WITH_DEFAULT(roughness_bias, "", "", 0, 1.0, float(0.0));
#include "used_float.fxh"

	#if !defined(COLORED_SPEC)
		DECLARE_FLOAT_WITH_DEFAULT(metalness_scalar, "", "", 0, 1.0, float(1.0));
		#include "used_float.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(metalness_bias, "", "", 0, 1.0, float(0.0));
		#include "used_float.fxh"
	#endif

DECLARE_BOOL_WITH_DEFAULT(detail_normals, "Detail Normals Enabled", "", false);
#include "next_bool_parameter.fxh"
DECLARE_SAMPLER(normal_detail_map, "Detail Normal Map", "detail_normals", "shaders/default_bitmaps/bitmaps/default_normal.tif");
#include "next_texture.fxh"
DECLARE_FLOAT_WITH_DEFAULT(detail_normal_intensity, "", "detail_normals", 0, 1.0, float(1.0));
#include "used_float.fxh"

	#if defined(SELFILLUM)
		DECLARE_SAMPLER(selfillum, "Self-Illum Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
		#include "next_texture.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(self_illum_color,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(self_illum_intensity,		"", "", 0, 1.0, float(0.0));
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
	float2 uv = pixel_shader_input.texcoord.xy;

	shader_data.common.albedo = sample2DGamma(color_map, transform_texcoord(uv, color_map_transform));
	shader_data.common.albedo.rgb *= pow(albedo_tint, .454545);	//power to fix h4 color gamma correction

	float4 pbr_masks = sample2DGamma(combo_map, transform_texcoord(uv, combo_map_transform));


		shader_data.shader_params.r	= pbr_masks.g;
		shader_data.shader_params.g	= saturate((1 - pbr_masks.a) * roughness_scalar + roughness_bias);
		shader_data.shader_params.b	= saturate(pbr_masks.r * metalness_scalar + metalness_bias);


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

		#if defined(CHANGE_COLOR)
		
			float4 control_map = sample2DGamma(tint_map, transform_texcoord(uv, tint_map_transform));
			// determine surface color
			// primary change color engine mappings, using temp values in maya for prototyping
			float4 primary_cc = 1.0;
			float3 secondary_cc = 1.0f;

			#if defined(cgfx)  || defined(ARMOR_PREVIS)
				primary_cc   = float4(tmp_primary_cc, 1.0);
				secondary_cc = float4(tmp_secondary_cc,1.0);
			#else
				primary_cc   = ps_material_object_parameters[0];
				secondary_cc = ps_material_object_parameters[1];
			#endif

			float3 surface_colors[3] = {base_color.rgb,
										secondary_cc.rgb,
										primary_cc.rgb};
			float3 surface_color;
			
			surface_color = primary_cc * control_map.r;
			surface_color += secondary_cc * control_map.g;
			surface_color += base_color * control_map.b;
			
			// output color
			shader_data.common.albedo.rgb = lerp(shader_data.common.albedo.rgb, surface_color, control_map.a);
		#endif


}

float4 pixel_lighting(
        in s_pixel_shader_input pixel_shader_input,
	    inout s_shader_data shader_data)
{
	//define stuff we need
	float4 albedo = shader_data.common.albedo;
	float4 shader_params = shader_data.shader_params;
    float3 normal = shader_data.common.normal;
	float3 view_dir = -shader_data.common.view_dir_distance.xyz;
	float3 diffuse = 0.0;
	float3 specular = 0.0;
	float3 reflection = 0.0;
	float4 out_color;
	float NDV = saturate(dot(view_dir, normal));

	//mix f0 and albedo by metalness.
	float3 metalness_color = lerp(float3(0.04,0.04,0.04), albedo.rgb, shader_params.b);
 /*------------------------------------SPECULAR CALCULATION------------------------------------*/
		//big thanks to the oomer for giving me an example on how to do these for loops!
	for (uint i = 0; i < shader_data.common.lighting_data.light_component_count; i++)
	{
		float4 light = shader_data.common.lighting_data.light_direction_specular_scalar[i];
		float3 color = shader_data.common.lighting_data.light_intensity_diffuse_scalar[i].rgb;

		//analytical lighting * light color * light intensity * f0
		specular = calc_specular_ggx_new(shader_params.g, normal, light.rgb, view_dir, metalness_color) * color * light.a * max(dot(normal, light.rgb), 0);
	}
 /*-------------------------------IN-DIRECT SPECULAR CALCULATION-------------------------------*/
	if (shader_data.common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && shader_data.common.lighting_mode != LM_PER_PIXEL_SIMPLE)
	{
		for (uint i = 0; i < 2; i++)
		{
			float3 light = VMFGetVector(shader_data.common.lighting_data.vmf_data, i);

			//final analytical lighting + VMF specular (indrect) * f0
			specular += VMFSpecularCustomEvaluate3(shader_data.common.lighting_data.vmf_data,
			calc_specular_ggx_new(shader_params.g, normal, light, view_dir, metalness_color), i) * max(dot(normal, light), 0);
		}
	}
 /*------------------------------------------DIFFUSE------------------------------------------*/
	calc_diffuse_oren_nayar(diffuse, shader_data.common, albedo.rgb, (1 / sqrt(2)) * atan(shader_params.g), normal, metalness_color);
 /*-----------------------------------------REFLECTION-----------------------------------------*/
 		//calculate reflection. roughness controls blurriness of cubemap. (won't look correct if cubemap only has a few mipmaps.)
	{
		float3 envmap_area_specular_only = 0.0;

    	calc_prebake_envtint(envmap_area_specular_only, shader_data.common, shader_data.common.normal, float2(0.45, 0.55), metalness_color, 1.0, 5);
		float3 rVec				= reflect(-view_dir, normal);
		float lod				= float_remap(pow(shader_params.g, .454545), 0, 1, 0, 8); // Exponential for smoother mip progression. remap attempts to push into proper mip range for 256x cubes. 
		float4 reflectionMap	= sampleCUBELOD(reflection_map, rVec, lod);
		reflection				= envmap_area_specular_only * reflectionMap.rgb * (reflectionMap.a + 1.0) * FresnelSchlickWithRoughness(metalness_color, NDV, 1-shader_params.g);
	}																			/*small reflection boost. looked good while testing, but will
																				remove if it ends up making reflections too bright for others.*/
 /*----------------------------------------FINAL OUTPUT----------------------------------------*/
	out_color.rgb = ((diffuse * albedo.rgb * (1-shader_params.b)) + specular + reflection) * shader_params.r;
	out_color.a = albedo.a;

	return out_color;
}

#include "techniques.fxh"
