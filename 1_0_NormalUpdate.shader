Shader "MasterProject/1_0_NormalUpdate" {

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

					float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
					float time = _Time.y * _WaveSpeed;
					
					//重点在这，正弦波公式
					float wave = _WaveInt * sin(worldPos.x * _WaveFreq + time);

					v.vertex.y += wave;

					o.pos = UnityObjectToClipPos(v.vertex);

					o.worldNormal = mul(v.normal, (float3x3)unity_ObjectToWorld);

					return o;
				
				}

				float4 frag(v2f i) : SV_Target {
					float3 worldNormal = normalize(i.worldNormal);

					float3 worldLightDir = normalize(_WorldSpaceLightPos0.xyz);

					float3 diffuse = _Diffuse.rgb * _LightColor0.rgb * saturate(dot(worldNormal, worldLightDir));

					fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz + ShadeSH9(float4(i.worldNormal, 1.0));

					float3 color = diffuse;// + ambient;

					return float4 (color, 1.0);
				}
			
			ENDCG

		}

	}
	Fallback "Diffuse"
}