#if !defined(__LIGHTING_REFLECTION_STUFF)
#define __LIGHTING_REFLECTION_STUFF

#include "core/core_types.fxh"
#include "lighting/vmf.fxh"


void calc_prebake_envtint_initializer(
	inout float3 specular,
	const in s_common_shader_data common,
	const in float3 normal,
	const in float2 raised_analytical_light_equation,
	const in float3 base_reflect,
	const in float3 angle_reflect,
	const in float fresnel_power)
{
	specular = 0.0f;

#if (defined(xenon) || (DX_VERSION == 11)) && !defined(DISABLE_VMF)

	if (common.lighting_mode != LM_PER_PIXEL_FLOATING_SHADOW_SIMPLE && common.lighting_mode != LM_PER_PIXEL_SIMPLE)
	{
		float4 direction_specular_scalar= common.lighting_data.light_direction_specular_scalar[0];
		float3 intensity= common.lighting_data.light_intensity_diffuse_scalar[0].rgb;

		float3 H[3] = {
			normalize(VMFGetVector(common.lighting_data.vmf_data, 0) - common.view_dir_distance.xyz),
			normalize(VMFGetVector(common.lighting_data.vmf_data, 1) - common.view_dir_distance.xyz),
			normalize(direction_specular_scalar.xyz - common.view_dir_distance.xyz) };
		float3 LdotN = float3(
			dot(VMFGetVector(common.lighting_data.vmf_data, 0), normal),
			dot(VMFGetVector(common.lighting_data.vmf_data, 1), normal),
			dot(direction_specular_scalar.xyz, normal));
		float3 HdotV = float3(
			dot(H[0], -common.view_dir_distance.xyz),
			dot(H[1], -common.view_dir_distance.xyz),
			dot(H[2], -common.view_dir_distance.xyz));

		float raised_analytical_light_equation_a = raised_analytical_light_equation.x;
		float raised_analytical_light_equation_b = raised_analytical_light_equation.y;

		float3 raised_analytical_dot_product= saturate(LdotN*raised_analytical_light_equation_a+raised_analytical_light_equation_b);

		float3 analytic_specular_radiance = raised_analytical_dot_product * 0.25f;// * lighting_coefficients[2].w;

		float3 F[3];
		
		// fresnel
		{
			F[0] = base_reflect+(angle_reflect-base_reflect)*pow((1.0-HdotV.x),fresnel_power);
			F[1] = base_reflect+(angle_reflect-base_reflect)*pow((1.0-HdotV.y),fresnel_power);
			F[2] = base_reflect+(angle_reflect-base_reflect)*pow((1.0-HdotV.z),fresnel_power);
		}

		float3 vmfSpecular = 
			VMFSpecularCustomEvaluateNoClamp(common.lighting_data.vmf_data, analytic_specular_radiance.x, 0) * F[0] +
			VMFSpecularCustomEvaluateNoClamp(common.lighting_data.vmf_data, analytic_specular_radiance.y, 1) * F[1];

		if (common.lighting_data.light_component_count > 0)
		{
			vmfSpecular += intensity * direction_specular_scalar.w * analytic_specular_radiance.z * F[2];
		}

		specular = vmfSpecular;
	}

#endif
}

void calc_prebake_envtint_inner_loop(
	inout float3 specular,
	const in s_common_shader_data common,
	const in float3 normal,
	const in float2 raised_analytical_light_equation,
	const in float3 base_reflect,
	const in float3 angle_reflect,
	const in float fresnel_power,
	int index)
{
#if (defined(xenon) || (DX_VERSION == 11)) && !defined(DISABLE_VMF)
	if (index > 1)
#else
	if (index < common.lighting_data.light_component_count)
#endif
	{
		float4 direction_specular_scalar= common.lighting_data.light_direction_specular_scalar[index];
		float3 intensity= common.lighting_data.light_intensity_diffuse_scalar[index].rgb;

		float3 H = normalize(direction_specular_scalar.xyz - common.view_dir_distance.xyz);
		float LdotN = saturate(dot(direction_specular_scalar, normal));
		float HdotV = saturate(dot(-common.view_dir_distance.xyz, H));

		float raised_analytical_light_equation_a = raised_analytical_light_equation.x;
		float raised_analytical_light_equation_b = raised_analytical_light_equation.y;

		float raised_analytical_dot_product= saturate(LdotN*raised_analytical_light_equation_a+raised_analytical_light_equation_b);

		float3 F;

		// fresnel
		{
			F=base_reflect+(angle_reflect-base_reflect)*pow((1-HdotV),fresnel_power);
		}

		float analytic_specular_radiance = F * raised_analytical_dot_product * 0.25f;// * lighting_coefficients[2].w;

		specular += analytic_specular_radiance * intensity * direction_specular_scalar.w;
	}
}

MAKE_ACCUMULATING_LOOP_5(float3, calc_prebake_envtint, float3, float2, float3, float3, float, MAX_LIGHTING_COMPONENTS);

#endif