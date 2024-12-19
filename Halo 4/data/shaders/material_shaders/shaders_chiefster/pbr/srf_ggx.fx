/* ----------------------------------------------------------
srf_ggx.fx
7/4/2024
a custom ggx material model.
by chiefster with help from chunch.
---------------------------------------------------------- */
#include "core/core.fxh"
#include "engine/engine_parameters.fxh"
#include "lighting/lighting.fxh"
#include "lighting/specular_model_ggx.fxh"
#include "lighting/diffuse_model_oren_nayar.fxh"
#include "lighting/reflectionstuff.fxh"

DECLARE_SAMPLER(color_map, "Albedo Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
#include "next_texture.fxh"

#if defined(COLORED_SPEC)
	DECLARE_SAMPLER(control_map, "Colored Specular Map", "", "shaders/default_bitmaps/bitmaps/default_spec.bitmap")
	#include "next_texture.fxh"
	DECLARE_SAMPLER(ao_map, "AO Map", "", "shaders/default_bitmaps/bitmaps/color_white.bitmap")
	#include "next_texture.fxh"
#else
	DECLARE_SAMPLER(control_map, "PBR ORM Map", "", "chiefster/bitmaps/default_orm.bitmap")
	#include "next_texture.fxh"
#endif


#if defined(CHANGE_COLOR)
	DECLARE_SAMPLER(cc_map, "Color Change Map", "", "shaders/default_bitmaps/bitmaps/default_diff.tif")
	#include "next_texture.fxh"
#endif

DECLARE_SAMPLER(normal_map, "Normal Map", "", "shaders/default_bitmaps/bitmaps/default_normal.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER_CUBE(reflection_map, "Reflection Map", "", "shaders/default_bitmaps/bitmaps/default_cube.tif")
#include "next_texture.fxh"

DECLARE_RGB_COLOR_WITH_DEFAULT(surface_color_tint, "", "", float3(1.0,1.0,1.0));
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

	#if defined(ARMOR_TEST)
		DECLARE_RGB_COLOR_WITH_DEFAULT(test_primary_cc,	"", "", float3(1,1,1));
		#include "used_float3.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(test_secondary_cc,	"", "", float3(1,1,1));
		#include "used_float3.fxh"
		#if defined(FOUR_CC)
			DECLARE_RGB_COLOR_WITH_DEFAULT(test_tertiary_cc,	"", "", float3(1,1,1));
			#include "used_float3.fxh"
			DECLARE_RGB_COLOR_WITH_DEFAULT(test_quaternary_cc,	"", "", float3(1,1,1));
			#include "used_float3.fxh"
		#endif
	#endif

	#if defined(USE_FRESNEL_MASK)
		DECLARE_RGB_COLOR_WITH_DEFAULT(normal_specular_tint,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(glancing_specular_tint,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(glancing_power,			"", "", 0, 1.0, float(1.0));
		#include "used_float.fxh"
	#endif

	#if defined(SELFILLUM)
		DECLARE_SAMPLER(selfillum, "Self-Illum Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
		#include "next_texture.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(self_illum_color,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(self_illum_intensity,		"", "", 0, 1.0, float(0.0));
		#include "used_float.fxh"
	#endif

	#if defined(ALPHA_CLIP)
		DECLARE_FLOAT_WITH_DEFAULT(clip_threshold,		"", "", 0, 1.0, float(0.3));
		#include "used_float.fxh"
	#endif

//DEBUG

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
	shader_data.common.albedo.rgb *= pow(surface_color_tint, .454545);	//power to "fix" h4 color gamma correction

	float4 pbr_masks = sample2DGamma(control_map, transform_texcoord(uv, control_map_transform));

	//define supported mask type

	#if defined(COLORED_SPEC) //assumes spec-gloss
	{
		shader_data.shader_params.rgb = pbr_masks.rgb;
		shader_data.shader_params.a = saturate((1 - pbr_masks.a) * roughness_scalar + roughness_bias);
		shader_data.common.shaderValues.x = sample2DGamma(ao_map, transform_texcoord(uv, ao_map_transform)).r;
	}

	#else
	{
		shader_data.shader_params.r	= pbr_masks.r;
		shader_data.shader_params.g	= saturate(pbr_masks.g * roughness_scalar + roughness_bias);
		shader_data.shader_params.b	= saturate(pbr_masks.b * metalness_scalar + metalness_bias);
		#if defined(USE_FRESNEL_MASK)
		{
			shader_data.shader_params.a	= pbr_masks.a;
		}
		#endif
	}
	#endif
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
	{
		float4 cc_mask = sample2DGamma(cc_map, transform_texcoord(uv, cc_map_transform));

		float3 primary_cc = 1.0;
		float3 secondary_cc = 1.0;
		#if defined(FOUR_CC)
			float3 tertiary_cc = 1.0;
			float3 quaternary_cc = 1.0;
		#endif

		#if defined(cgfx) || defined(ARMOR_TEST)
		{
			primary_cc = test_primary_cc;
			secondary_cc = test_secondary_cc;
			#if defined(FOUR_CC)
			{
				tertiary_cc = test_tertiary_cc;
				quaternary_cc = test_quaternary_cc;
			}
			#endif
		}
		#else
		{
			primary_cc   = ps_material_object_parameters[0];
			secondary_cc = ps_material_object_parameters[1];
			#if defined(FOUR_CC)
			{
				tertiary_cc   = ps_material_object_parameters[2];
				quaternary_cc = ps_material_object_parameters[3];
			}
			#endif
		}
		#endif

		#if !defined(FOUR_CC)
		{
			shader_data.common.albedo.rgb *=((1.0f - cc_mask.r) + cc_mask.r * primary_cc) *
											((1.0f - cc_mask.g) + cc_mask.g * secondary_cc);
		}
		#else
		{
			shader_data.common.albedo.rgb *=((1.0f - cc_mask.r) + cc_mask.r * primary_cc) *
											((1.0f - cc_mask.g) + cc_mask.g * secondary_cc) *
											((1.0f - cc_mask.b) + cc_mask.b * tertiary_cc) *
											((1.0f - cc_mask.a) + cc_mask.a * quaternary_cc);
		}
		#endif
	}
	#endif
}

float4 pixel_lighting(
        in s_pixel_shader_input pixel_shader_input,
	    inout s_shader_data shader_data)
{
	float4 albedo = shader_data.common.albedo;
	float4 shader_params = shader_data.shader_params;
    float3 normal = shader_data.common.normal;
	float3 view_dir = -shader_data.common.view_dir_distance.xyz;
	float3 diffuse = 0.0;
	float3 specular = 0.0;
	float3 reflection = 0.0;
	float4 out_color = 0.0;
	float NDV = saturate(dot(view_dir, normal));
	//calculate F0/metalness_color.
	#if defined(COLORED_SPEC)
		float3 metalness_color = max(shader_params.rgb, 0.04); //test so that the textures don't always kill the specular if they end up black due to compression, etc.
		shader_params.g = shader_params.a;
	#else
		//mix base F0 and albedo by metalness.
		float3 metalness_color = lerp(float3(0.04,0.04,0.04), albedo.rgb, shader_params.b);
	#endif

	#if defined(USE_FRESNEL_MASK)
    {							//power to "fix" h4 color gamma correction. may remove if it causes issues later on.
		float3 spec_colors = lerp(pow(normal_specular_tint, 0.454545), pow(glancing_specular_tint, 0.454545), pow(1-NDV, glancing_power)); //mix spec colors by view angle.
		spec_colors = lerp(float3(1,1,1), spec_colors, shader_params.a); //mask spec colors by spec color mask.
		metalness_color *= lerp(spec_colors, float3(1,1,1),  pow(1-NDV,5));
	}
	#endif
 /*------------------------------------SPECULAR CALCULATION------------------------------------*/
	/*calculate specular. should place all of this into a .fxh file for cleanliness.
	big thanks to the oomer for giving me an example on how to do these for loops!*/
	for (uint i = 0; i < shader_data.common.lighting_data.light_component_count; i++)
	{
		float4 light = shader_data.common.lighting_data.light_direction_specular_scalar[i];
		float3 color = shader_data.common.lighting_data.light_intensity_diffuse_scalar[i].rgb;
		float NDL = max(dot(normal, light.rgb), 0.0);

		//OLI'S COMMENT: Changed it so it multiplies by NDL at the end instead of fresnel. Fresnel shouldn't be here anyway.
		specular = calc_specular_ggx_new(shader_params.g, normal, light.rgb, view_dir, metalness_color) * color * light.a * NDL;
	}
 /*-------------------------------IN-DIRECT SPECULAR CALCULATION-------------------------------*/
	if (shader_data.common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && shader_data.common.lighting_mode != LM_PER_PIXEL_SIMPLE)
	{
		for (uint i = 0; i < 2; i++)
		{
			float3 light = VMFGetVector(shader_data.common.lighting_data.vmf_data, i);
			float NDL = max(dot(normal, light), 0.0);

			specular += VMFSpecularCustomEvaluate3(shader_data.common.lighting_data.vmf_data,
			calc_specular_ggx_new(shader_params.g, normal, light, view_dir, metalness_color), i) * NDL;
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
	#if defined(COLORED_SPEC)
	{
		out_color.rgb = ((diffuse * albedo.rgb) + specular + reflection) * shader_data.common.shaderValues.x;
	}
	#else
	{
		out_color.rgb = ((diffuse * albedo.rgb * (1-shader_params.b)) + specular + reflection) * shader_params.r;
	}
	#endif
	#if defined(ALPHA_CLIP)
		clip(albedo.a - clip_threshold);
	#endif
	out_color.a = albedo.a;
 /*-----------------------------------------SELF-ILLUM-----------------------------------------*/
	#if defined(SELFILLUM)
		if (AllowSelfIllum(shader_data.common))
		{
			float3 self_illum = sample2DGamma(selfillum, transform_texcoord(pixel_shader_input.texcoord.xy, selfillum_transform));
			out_color.rgb += self_illum * self_illum_color * self_illum_intensity;
			shader_data.common.selfIllumIntensity = GetLinearColorIntensity(self_illum);
		}
	#endif

	return out_color;
}

#include "techniques.fxh"
