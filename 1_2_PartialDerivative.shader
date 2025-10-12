Shader "MasterProject/1_2_PartialDerivative" {

	Properties {
		_Diffuse ("Diffuse", Color) = (1, 1, 1, 1)
		_WaveInt ("Wave Intensity", Float) = 1.0
		_WaveFreq ("Wave Freqency", Float) = 1.0
		_WaveSpeed ("Wave Speed", Float) = 1.0
	}

	SubShader {

		Pass {

			Tags { "LightMode" = "ForwardBase" }

			CGPROGRAM

				#pragma vertex vert
				#pragma fragment frag

				#include "Lighting.cginc"

				float4 _Diffuse;
				float _WaveInt;
				float _WaveFreq;
				float _WaveSpeed;

                struct a2v{
                    float4 vertex : POSITION;
					float3 normal : NORMAL;
                };

                struct v2f{
                   float4 pos : SV_POSITION;
				   float3 worldNormal : TEXCOORD0;
                };

				v2f vert(a2v v) {
					v2f o;

					float time = _Time.y * _WaveSpeed;

					//还是正弦波公式，不过加入了Z轴方向的波
					float wave = _WaveInt * sin(v.vertex.x * _WaveFreq + time) + _WaveInt * sin(v.vertex.z * _WaveFreq + time);
					v.vertex.y += wave;
					
					//分别计算在x和z方向上的偏导数
					float d_dx = _WaveInt * _WaveFreq * cos(v.vertex.x * _WaveFreq + time);
					float d_dz = _WaveInt * _WaveFreq * cos(v.vertex.z * _WaveFreq + time);

					v.normal = normalize(float3(-d_dx, 1, -d_dz));

					o.pos = UnityObjectToClipPos(v.vertex);

					o.worldNormal = mul(v.normal, (float3x3)unity_ObjectToWorld);

					return o;
				
				}

				float4 frag(v2f i) : SV_Target {
					float3 worldNormal = normalize(i.worldNormal);

					float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);

					float3 diffuse = _Diffuse.rgb * _LightColor0.rgb * saturate(dot(worldNormal, worldLightDir));

					float3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz + ShadeSH9(float4(i.worldNormal, 1.0));//����ShaderSH9����ȡ��Skybox����������

					float3 color = diffuse;// + ambient;

					return float4 (color, 1.0);
				}
			
			ENDCG 

		}

	}
	Fallback "Diffuse"
}