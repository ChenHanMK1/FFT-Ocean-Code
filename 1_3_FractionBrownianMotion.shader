// Upgrade NOTE: replaced '_World2Object' with 'unity_WorldToObject'
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "MasterProject/1_3_FractionBrownianMotion" {

	Properties {
		//����һ������ɫ
		_Diffuse ("Diffuse", Color) = (1, 1, 1, 1)
		_Gloss ("Gloss", Float) = 1.0
		_SpecPow ("Specular Power", Float) = 1.0
		_WaveInt ("Wave Intensity", Float) = 1.0
		_WaveFreq ("Wave Freqency", Float) = 1.0
		_WaveSpeed ("Wave Speed", Float) = 1.0
		_WaveAmount ("Wave Amount", Int) = 1
		_PeekSharp ("Peek Sharpness", Float) = 1.0
		_NormalInt ("Normal Intensity", Float) = 1.0
		_FBM_Int ("FBM Intensity", Range(0.0, 1.0)) = 0.82
		_FBM_Fre ("FBM Frequent", Range(1.0, 2.0)) = 1.18
		_FBM_Spe ("FBM Speed", Range(0.0, 2.0)) = 1.2
	}

	SubShader {

		Pass {

			//��������Ҫ��Tags
			Tags { "LightMode" = "ForwardBase" }
			Tags { "RenderType" = "Opaque" }
			LOD 200

			CGPROGRAM
				
				//���������������ֱ���Ϊ������ɫ����ƬԪ��ɫ��
				#pragma vertex vert
				#pragma fragment frag

				#pragma target 3.0

				//����Unity�Ĺ����ļ�
				#include "Lighting.cginc"

				//����
				float4 _Diffuse;
				float _Gloss;
				float _SpecPow;
				float _WaveInt;
				float _WaveFreq;
				float _WaveSpeed;
				int _WaveAmount;
				float _PeekSharp;
				float _NormalInt;
				float _FBM_Int;
				float _FBM_Fre;
				float _FBM_Spe;

				float random(float2 seed){
					return frac(sin(dot(seed, float2(12.9898, 78.233))) * 43758.5453) * 360;
				}

                struct a2v{
                    float4 vertex : POSITION;
					float3 normal : NORMAL;

                };

                struct v2f{
                   float4 pos : SV_POSITION;
				   float3 worldNormal : TEXCOORD0;
				   float3 worldPos : TEXCOORD1;
                };

				v2f vert(a2v v) {

					v2f o;

					float wave = 0;
					float waveInt = _WaveInt * 0.1;
					float waveFreq = _WaveFreq;
					float waveSpeed = _WaveSpeed;
					float d_dx = 0;
					float d_dz = 0;
					float time = _Time.y * waveSpeed;
					
					//最重要的for循环，海浪数量就等于参数 _WaveAmount
                    for (int i = 1; i <= _WaveAmount; i++) {
						
						//每次循环都生成随机方向（伪随机）
						float angle = radians(random(float2(i * 0.2, i * 0.2)));
						float cosA = cos(angle);
						float sinA = sin(angle);

						//旋转x轴坐标（向量旋转公式）
						float rotatedX = v.vertex.x * cosA + v.vertex.z * sinA;
						//用旋转后的坐标带入正弦波公式
						wave += waveInt * sin(rotatedX * waveFreq + time);

						//同样地求x和z方向的偏导数，注意也要引入随机方向cosA和sinA
						d_dx += waveInt * waveFreq * (cos(rotatedX * waveFreq + time) * cosA);
						d_dz += waveInt * waveFreq * (cos(rotatedX * waveFreq + time) * sinA);

						//引入分型布朗运动FBM，每次循环都更新
						waveInt *= _FBM_Int;
						waveFreq *= _FBM_Fre;
					}

					//法线等于切线和副切线的叉乘，最终结果就是（-d_dx, 1, -d_dz）
					//推导过程问AI :)
					v.normal = normalize(float3(-d_dx * _NormalInt, 1, -d_dz * _NormalInt));
					v.vertex.y += wave;		

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
					float3 ambient = UNITY_LIGHTMODEL_AMBIENT.rgb + ShadeSH9(float4(worldNormal, 1.0));

					float3 color = diffuse + spec;// + ambient;

					return float4 (color, 1.0);
				}
			
			ENDCG

		}

	}
	Fallback "Diffuse"
}