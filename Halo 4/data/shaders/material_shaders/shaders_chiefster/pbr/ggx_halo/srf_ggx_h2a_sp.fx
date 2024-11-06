/* ----------------------------------------------------------
srf_ggx_h2a_sp.fx
11/3/2024
a custom ggx material model.
by chiefster with help from chunch.
alternate version that tries to emulate H2ASP's wack shader.
---------------------------------------------------------- */
#include "core/core.fxh"
#include "engine/engine_parameters.fxh"
#include "lighting/lighting.fxh"
#include "lighting/specular_model_ggx.fxh"



DECLARE_SAMPLER(color, "Albedo Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
#include "next_texture.fxh"

		#if defined(H5_SUPPORT)
			DECLARE_SAMPLER(masks, "Control Map", "", "chiefster/bitmaps/default_control.bitmap")
			#include "next_texture.fxh"
		#elif defined(H2AMP_SUPPORT)
			DECLARE_SAMPLER(masks, "Combo Map", "", "chiefster/bitmaps/default_combo.bitmap")
			#include "next_texture.fxh"
		#elif defined(COLORED_SPEC)
			DECLARE_SAMPLER(masks, "Colored Specular Map", "", "shaders/default_bitmaps/bitmaps/default_spec.bitmap")
			#include "next_texture.fxh"
		#else
			DECLARE_SAMPLER(masks, "PBR ORM Map", "", "chiefster/bitmaps/default_orm.bitmap")
			#include "next_texture.fxh"
		#endif

DECLARE_SAMPLER(norm, "Normal Map", "", "shaders/default_bitmaps/bitmaps/default_normal.bitmap")
#include "next_texture.fxh"
DECLARE_SAMPLER_CUBE(reflection_map, "Reflection Map", "", "shaders/default_bitmaps/bitmaps/default_cube.tif")
#include "next_texture.fxh"

DECLARE_RGB_COLOR_WITH_DEFAULT(surface_color_tint,	"", "", float3(1.0,1.0,1.0));
#include "used_float3.fxh"
DECLARE_FLOAT_WITH_DEFAULT(roughness_scalar,	"", "", 0, 1.0, float(1.0));
#include "used_float.fxh"
DECLARE_FLOAT_WITH_DEFAULT(roughness_bias,		"", "", 0, 1.0, float(0.0));
#include "used_float.fxh"

	#if defined(SELFILLUM)
		DECLARE_SAMPLER(selfillum, "Self-Illum Map", "", "shaders/default_bitmaps/bitmaps/default_diff.bitmap")
		#include "next_texture.fxh"
		DECLARE_RGB_COLOR_WITH_DEFAULT(self_illum_color,	"", "", float3(1.0,1.0,1.0));
		#include "used_float3.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(self_illum_intensity,		"", "", 0, 1.0, float(0.0));
		#include "used_float.fxh"
	#endif

	#if defined(PARALLAX)
		DECLARE_SAMPLER(height_map, "Height Map", "Height Map", "shaders/default_bitmaps/bitmaps/default_diff.tif")
		#include "next_texture.fxh"
		DECLARE_FLOAT_WITH_DEFAULT(height_scale, "Height Scale", "", 0, 0.1, float(0.1));
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

    float2 color_uv    = transform_texcoord(uv, color_transform);
	shader_data.common.albedo = sample2DGamma(color, color_uv);
	shader_data.common.albedo.rgb *= pow(surface_color_tint, .454545);	//power to fix h4 color gamma correction

    float2 normal_uv    = transform_texcoord(uv, norm_transform);
    shader_data.common.normal = sample_2d_normal_approx(norm, normal_uv);
	shader_data.common.normal = mul(shader_data.common.normal, shader_data.common.tangent_frame);

	float2 masks_uv    = transform_texcoord(uv, masks_transform);
	float4 pbr_masks = sample2DGamma(masks, masks_uv);
	shader_data.shader_params = pbr_masks;
	shader_data.shader_params.a = (1-shader_data.shader_params.a) * roughness_scalar;// + roughness_bias;
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
	float3 metalness_color = lerp(shader_params.rgb, float3(0.5,0.5,0.5), pow(NDV, 5));
/*------------------------------------SPECULAR CALCULATION------------------------------------*/

		//big thanks to the oomer for giving me an example on how to do these for loops!
	for (uint i = 0; i < shader_data.common.lighting_data.light_component_count; i++)
	{
		float4 light = shader_data.common.lighting_data.light_direction_specular_scalar[i];
		float3 color = shader_data.common.lighting_data.light_intensity_diffuse_scalar[i].rgb;

		//analytical lighting * light color * light intensity * f0
		specular = calc_specular_ggx(shader_params.g, normal, light.rgb, view_dir) * color * light.a *
		(metalness_color + ((1-metalness_color) * pow(1-dot(normalize(light.rgb + view_dir), normal), 5)));
	}


/*-------------------------------IN-DIRECT SPECULAR CALCULATION-------------------------------*/


	if (shader_data.common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && shader_data.common.lighting_mode != LM_PER_PIXEL_SIMPLE)
	{
		for (uint i = 0; i < 2; i++)
		{
			float3 light = VMFGetVector(shader_data.common.lighting_data.vmf_data, i);

			//final analytical lighting + VMF specular (indrect) * f0
			specular += VMFSpecularCustomEvaluate3(shader_data.common.lighting_data.vmf_data, calc_specular_ggx(shader_params.g, normal, light, view_dir), i) *
			(metalness_color + ((1-metalness_color) * pow(1-dot(normalize(light + view_dir), normal), 5)));
		}
	}


/*------------------------------------------DIFFUSE------------------------------------------*/

	calc_diffuse_lambert(diffuse, shader_data.common, normal);
/*-----------------------------------------REFLECTION-----------------------------------------*/

	//calculate reflection. roughness controls blurriness of cubemap. (won't look correct if cubemap only has a few mipmaps.)
	float3 rVec				= reflect(-view_dir, normal);
	float lod				= pow(shader_params.a, roughness_bias) * 7; // Exponential for smoother mip progression. scalar to push into proper baked cube mip range (256 res cubes have 8 mips)
	float4 reflectionMap	= sampleCUBELOD(reflection_map, rVec, lod);
	float3 reflection		= diffuse * (reflectionMap.rgb * 4.59479) * reflectionMap.a * metalness_color; //4.59479 value is from H3's albedo.fx. thanks bungo

/*----------------------------------------FINAL OUTPUT----------------------------------------*/
    float4 out_color;
	out_color.rgb = (diffuse * albedo.rgb) + specular + reflection;
	out_color.a = albedo.a;
	return out_color;
}

#include "techniques.fxh"
