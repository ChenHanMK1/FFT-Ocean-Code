Shader "MasterProject/2_1_GerstnerWave" {

	Properties {
		_Diffuse ("Diffuse", Color) = (1, 1, 1, 1)
		_Gloss ("Gloss", Float) = 1.0
		_SpecPow ("Specular Power", Float) = 1.0
		_PeekSharp ("Peek Sharpness", Range(0.0, 1.0)) = 0.5
		_WaveLength ("Wavelength", Float) = 1.0
		_WaveAmount ("Wave Amount", Int) = 1
		_WaveSpeed ("Wave Speed", Range(0.0, 1.0)) = 0.5
		_NormalInt ("Normal Intensity", Float) = 1.0
		_FBM_Amp ("FBM Amplitude", Range(0.0, 1.0)) = 0.82
		_FBM_Fre ("FBM Frequent", Range(1.0, 2.0)) = 1.18
		_FBM_Time ("FBM Time", Range(0.0, 2.0)) = 0.82
	}

	SubShader {

		

		Pass {

			Tags { "LightMode" = "ForwardBase" }
			Tags { "RenderType" = "Opaque" }
			LOD 200

			CGPROGRAM
				
				#pragma vertex vert
				#pragma fragment frag

				#pragma target 3.0
				#pragma multi_compile_fwdbase

				#include "Lighting.cginc"

				float2 random(float2 st){
					st = float2(
						dot(st, float2(127.1, 311.7)),
						dot(st, float2(269.5, 183.3))
					);
					return frac(sin(st) * 43758.5453123) * 2 - 1; // ��� float2
				}

				float4 _Diffuse;
				float _Gloss, _SpecPow;

				float _WaveLength, _PeekSharp, _WaveSpeed;
				int _WaveAmount;

				float _NormalInt;

				float _FBM_Amp, _FBM_Fre, _FBM_Time;


                struct a2v{
                    float4 vertex : POSITION;
					float3 normal : NORMAL;
					float2 uv : TEXCOORD0;

                };

                struct v2f{
                   float4 pos : SV_POSITION;
				   float3 worldNormal : TEXCOORD0;
				   float3 worldPos : TEXCOORD1;
                };

				v2f vert(a2v v) {

					v2f o;

					float waveMap = 0;
					float temp_x = v.vertex.x;
					float temp_y = v.vertex.y;
					
					float3 totalOffset = float3(0, 0, 0);
					float3 grad = float3(0, 0, 0);
					float deri_x = 0;
					float deri_y = 0;

					
                    for (int i = 1; i <= _WaveAmount; i++) {
						float goldenAngle = 2.39996323;// radians
						float angle = i * goldenAngle;
						float2 dir = float2(cos(angle), sin(angle));

						float k = 2 * UNITY_PI / _WaveLength * pow(_FBM_Fre, i - 1);
						float a = 0.2 * _PeekSharp * pow(_FBM_Amp, i - 1) / k;
						float c = sqrt(9.8 / k); 

						float f = k * (dot(dir, v.vertex.xz) - _Time.y * c * _WaveSpeed);

						totalOffset.x += dir.x * a * cos(f);
						totalOffset.y += a * sin(f);
						totalOffset.z += dir.y * a * cos(f);

						grad.x += -dir.x * a * k * cos(f);
						grad.z += -dir.y * a * k * cos(f);
					}

					v.vertex.xyz += totalOffset;

					float3 normal = normalize(float3(grad.x * _NormalInt, 1.0, grad.z * _NormalInt));
					v.normal = normal;

					v.vertex.xyz += totalOffset;

					//v.normal = normalize(float3(-deri_y, deri_x, 0));
					//v.vertex.xyz = float3(temp_x, temp_y, v.vertex.z);		

					o.pos = UnityObjectToClipPos(v.vertex);
					o.worldPos = mul(unity_ObjectToWorld, v.vertex);

					o.worldNormal = normalize(mul((float3x3)unity_ObjectToWorld, v.normal));

					return o;
				
				}

				float4 frag(v2f i) : SV_Target {
					float3 worldNormal = normalize(i.worldNormal);

					float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);

					float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);
					float3 halfDir = normalize(worldLightDir + viewDir);

					float3 spec = _SpecPow * pow(max(0, dot(worldNormal, halfDir)), _Gloss) * _LightColor0.rgb;
					float3 diffuse = _Diffuse.rgb * _LightColor0.rgb * saturate(dot(worldNormal, worldLightDir));
					float3 ambient = ShadeSH9(float4(worldNormal, 1.0));

					float3 color = diffuse + spec;// + ambient;

					return float4 (color, 1.0);
				}
			
			ENDCG

		}

	}
	Fallback "Diffuse"
}