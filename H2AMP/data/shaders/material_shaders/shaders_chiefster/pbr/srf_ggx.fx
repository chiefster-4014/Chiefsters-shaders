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

DECLARE_SAMPLER(color_map, "Albedo Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
#include "next_texture.fxh"

#elif defined(H2AMP_SUPPORT)
	DECLARE_SAMPLER(control_map, "Combo Map", "", "chiefster/bitmaps/default_combo.bitmap")
	#include "next_texture.fxh"
#elif defined(COLORED_SPEC)
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
	shader_data.common.albedo.rgb *= pow(surface_color_tint, .454545);	//power to fix h4 color gamma correction

	float4 pbr_masks = sample2DGamma(control_map, transform_texcoord(uv, control_map_transform));

	//define supported mask type
	#if defined(H2AMP_SUPPORT) //same mask type as Unity standard for some reason
	{
		shader_data.shader_params.r	= pbr_masks.g;
		shader_data.shader_params.g	= saturate((1 - pbr_masks.a) * roughness_scalar + roughness_bias);
		shader_data.shader_params.b	= saturate(pbr_masks.r + metalness_bias);
	}

	#elif defined(COLORED_SPEC) //assumes spec-gloss
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

	float NDV = saturate(dot(view_dir, normal));
 /*-------------------------------------------SHADER-------------------------------------------*/

	#if defined(COLORED_SPEC)
		float3 metalness_color = max(shader_params.rgb, 0.1);
	#else
		//mix f0 and albedo by metalness.
		float3 metalness_color = lerp(float3(0.06,0.06,0.06), albedo.rgb, shader_params.b);
	#endif

	#if defined(USE_FRESNEL_MASK)
    {							//power to fix h4 color gamma correction 
		float3 spec_colors = lerp(pow(normal_specular_tint, 0.454545), pow(glancing_specular_tint, 0.454545), pow(1-NDV, glancing_power)); //mix spec colors by view angle.
		spec_colors = lerp(float3(1,1,1), spec_colors, shader_params.a); //mask spec colors by spec color mask.
		metalness_color *= lerp(spec_colors, float3(1,1,1),  pow(1-NDV,5));
	}
	#endif

	#if defined(COLORED_SPEC)
	{
		shader_params.g = shader_params.a;
	}
	#endif

 /*------------------------------------SPECULAR CALCULATION------------------------------------*/
			//big thanks to the oomer for giving me an example on how to do these for loops!
		for (uint i = 0; i < shader_data.common.lighting_data.light_component_count; i++)
		{
			float4 light = shader_data.common.lighting_data.light_direction_specular_scalar[i];
			float3 color = shader_data.common.lighting_data.light_intensity_diffuse_scalar[i].rgb;

			//analytical lighting * light color * light intensity * f0
			specular = calc_specular_ggx(shader_params.g, normal, light.rgb, view_dir) * color * light.a *
				get_fresnel_shlick(metalness_color, normal, light.rgb + view_dir) * max(dot(normal, light.rgb), 0);
		}
 /*-------------------------------IN-DIRECT SPECULAR CALCULATION-------------------------------*/
		if (shader_data.common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && shader_data.common.lighting_mode != LM_PER_PIXEL_SIMPLE)
		{
			for (uint i = 0; i < 2; i++)
			{
				float3 light = VMFGetVector(shader_data.common.lighting_data.vmf_data, i);

				//final analytical lighting + VMF specular (indrect) * f0
				specular += VMFSpecularCustomEvaluate3(shader_data.common.lighting_data.vmf_data, calc_specular_ggx(shader_params.g, normal, light, view_dir), i) *
				get_fresnel_shlick(metalness_color, normal, light + view_dir) * max(dot(normal, light), 0);
			}
		}
 /*------------------------------------------DIFFUSE------------------------------------------*/
		calc_diffuse_oren_nayar(diffuse, shader_data.common, albedo.rgb, shader_params.g, normal);
 /*-----------------------------------------REFLECTION-----------------------------------------*/
	float3 reflection = 0.0;
		//calculate reflection. roughness controls blurriness of cubemap. (won't look correct if cubemap only has a few mipmaps.)
		float3 rVec				= reflect(-view_dir, normal);
		float lod				= pow(shader_params.g, 0.34f) * 6.5f; // Exponential for smoother mip progression. scalar attempts to push into proper baked cube mip range. 
		float4 reflectionMap	= sampleCUBELOD(reflection_map, rVec, lod);
		reflection				= diffuse * reflectionMap.rgb * reflectionMap.a * get_fresnel_shlick(metalness_color, normal, view_dir);
 /*----------------------------------------FINAL OUTPUT----------------------------------------*/

	float4 out_color = 0.0;
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
