Shader "MasterProject/FFTOcean_Shader"
{
    //细分相关计算
    CGINCLUDE
    //#define _TessEdgeLength 10
    int _TessEdgeLength;

    struct TessellationFactors{
        float edge[3] : SV_TESSFACTOR;
        float inside : SV_INSIDETESSFACTOR;
    };
    
    //细分启动式
    float TessellationHeuristic(float3 cp1, float3 cp2){
        float edgeLength = distance(cp1, cp2);
        float3 edgeCenter = (cp1 + cp2) * 0.5;
        float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

        return edgeLength * _ScreenParams.y / (_TessEdgeLength * pow(viewDistance * 0.5f, 1.2f));
    }

    bool TriIsBelowClip (float3 p0, float3 p1, float3 p2, int planeIndex, float bias){
        float4 clipPlane = unity_CameraWorldClipPlanes[planeIndex];

        return dot(float4(p0, 1), clipPlane) < bias && dot(float4(p1, 1), clipPlane) < bias && dot(float4(p2, 1), clipPlane) < bias;
    }

    bool cullTriangle (float3 p0, float3 p1, float3 p2, float bias){
        return TriIsBelowClip(p0, p1, p2, 0, bias) ||
                TriIsBelowClip(p0, p1, p2, 1, bias) ||
                TriIsBelowClip(p0, p1, p2, 2, bias) ||
                TriIsBelowClip(p0, p1, p2, 3, bias);
    }

    ENDCG

    Properties
    {

    }
    SubShader
    {
        //基础着色pass
        pass{
            Tags { "LightMode" = "ForwardBase" }
            Tags { "RenderType"="Opaque" }
            LOD 200

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_fwdbase

            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"

            #pragma vertex vert
            #pragma hull hull
            #pragma domain domain
            #pragma geometry geo
            #pragma fragment frag

            UNITY_DECLARE_TEX2DARRAY(_DisplacementTexture);
            UNITY_DECLARE_TEX2DARRAY(_SlopeTexture);
            UNITY_DECLARE_TEX2D(_VariationMask);

            sampler2D _CameraDepthNormalsTexture;

            float _DisplaceDepthAttenuation, _FoamDepthAttenuation;

            float _Tile0, _Tile1, _Tile2, _Tile3, _LayerContribute0, _LayerContribute1, _LayerContribute2, _LayerContribute3;

            float _NormalStrength, _HeightStrength;

            float3 _ScatterColor, _ScatterPeakColor, _FoamColor, _AmbientColor, _FogColor;

            float _AmbientDensity;

            float _WavePeakScatterStrength, _ScatterStrength, _ScatterShadowStrength;

            float _FoamRoughness, _Roughness, _EnvirLightStrength;

            float _EdgeFoamPower, _ShadowIntensity, _FogDensity, _FogPower;

            float _VarMaskRange, _VarMaskPower, _VarMaskTexScale;

            struct a2h
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 _ShadowCoord : TEXCOORD1;
            };

            struct h2d
            {
                float4 vertex : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 _ShadowCoord : TEXCOORD1;
            };

            struct v2g
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float clipDepth : TEXCOORD3;
                float viewDepth : TEXCOORD4;
                float2 screenUV : TEXCOORD5;
                float4 _ShadowCoord : TEXCOORD6;
            };

            struct g2f
            {
                v2g data;
                float2 barycentricCoordinates : TEXCOORD9;
                float4 _ShadowCoord : TEXCOORD10;
            };

            h2d vert(a2h h)
            {
                h2d d;
				d.vertex = h.vertex;
				d.uv = h.uv;
                d.normal = h.normal;
                d._ShadowCoord = h._ShadowCoord;

				return d;
            }

            float DotClamped(float3 a, float3 b) {
                return saturate(dot(a, b));
            }

            v2g vp(h2d d)
            {
                v2g g;

                g.worldPos = mul(unity_ObjectToWorld, d.vertex);

                float3 displacement0 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(g.worldPos.xz * _Tile0, 0), 0) * _LayerContribute0;
                float3 displacement1 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(g.worldPos.xz * _Tile1, 1), 0) * _LayerContribute1;
                float3 displacement2 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(g.worldPos.xz * _Tile2, 2), 0) * _LayerContribute2;
                float3 displacement3 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(g.worldPos.xz * _Tile3, 3), 0) * _LayerContribute3;
                float3 displacement = displacement0 + displacement1 + displacement2 + displacement3;

                float4 clipPos = UnityObjectToClipPos(d.vertex);
                float clipDepth = 1 - Linear01Depth(clipPos.z / clipPos.w);
                
                displacement = lerp(0.0f, displacement, pow(saturate(clipDepth), _DisplaceDepthAttenuation));
                d.vertex.xyz += mul(unity_WorldToObject, displacement.xyz);

                clipPos = UnityObjectToClipPos(d.vertex);
                float2 screenUV = ((clipPos.xy / clipPos.w) + 1) / 2;
                screenUV.y = 1 - screenUV.y;
                float viewDepth = -mul(UNITY_MATRIX_MV, d.vertex).z * _ProjectionParams.w;
                
                g.pos = UnityObjectToClipPos(d.vertex);
                g.worldNormal = normalize(mul((float3x3)unity_ObjectToWorld, d.normal));
                g.uv = g.worldPos.xz;
                g.clipDepth = clipDepth;
                g.viewDepth = viewDepth;
                g.screenUV = screenUV;

                TRANSFER_SHADOW(g);
           
                return g;
            }

            TessellationFactors PatchFunction(InputPatch < h2d, 3 > patch)
            {
                TessellationFactors f;

                float3 p0 = mul(unity_ObjectToWorld, patch[0].vertex);
                float3 p1 = mul(unity_ObjectToWorld, patch[1].vertex);
                float3 p2 = mul(unity_ObjectToWorld, patch[2].vertex);

                float bias = -0.5 * 100;

                if(cullTriangle(p0, p1, p2, bias))
                {
                    f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
                }else{
                    f.edge[0] = TessellationHeuristic(p1, p2);
                    f.edge[1] = TessellationHeuristic(p2, p0);
                    f.edge[2] = TessellationHeuristic(p0, p1);
                    f.inside = (TessellationHeuristic(p1, p2) +
                                TessellationHeuristic(p2, p0) +
                                TessellationHeuristic(p0, p1)) * (1.0f / 3.0f);
                }

                return f;
            }

            [UNITY_domain("tri")]
            [UNITY_outputcontrolpoints(3)]
            [UNITY_outputtopology("triangle_cw")]
            [UNITY_partitioning("integer")]
            [UNITY_patchconstantfunc("PatchFunction")]

            h2d hull(InputPatch < h2d, 3 > patch, uint id : SV_OUTPUTCONTROLPOINTID)
            {
                return patch[id];
            }

            #define DP_INTERPOLATE(fieldName) data.fieldName = \
                                     patch[0].fieldName * barycentricCoordinates.x + \
                                     patch[1].fieldName * barycentricCoordinates.y + \
                                     patch[2].fieldName * barycentricCoordinates.z;


            [UNITY_domain("tri")]
            v2g domain(TessellationFactors factors, OutputPatch < h2d, 3 > patch, float3 barycentricCoordinates : SV_DOMAINLOCATION)
            {
                a2h data = (a2h)0;
                DP_INTERPOLATE(vertex)
                DP_INTERPOLATE(uv)
                DP_INTERPOLATE(normal)
                DP_INTERPOLATE(_ShadowCoord)

                return vp(data);
            }

            [maxvertexcount(3)]
            void geo(triangle v2g g[3], inout TriangleStream<g2f> stream)
            {
                g2f g0, g1, g2;
                g0.data = g[0];
                g1.data = g[1];
                g2.data = g[2];

                g0.barycentricCoordinates = float2(1, 0);
                g1.barycentricCoordinates = float2(0, 1);
                g2.barycentricCoordinates = float2(0, 0);

                g0._ShadowCoord = g[0]._ShadowCoord;
                g1._ShadowCoord = g[1]._ShadowCoord;
                g2._ShadowCoord = g[2]._ShadowCoord;

                stream.Append(g0);
                stream.Append(g1);
                stream.Append(g2);
            }

            float Beckmann (float nDoth, float Roughness)
            {
                float exp_arg = (nDoth * nDoth - 1) / (Roughness * Roughness * nDoth * nDoth);
                return exp(exp_arg) / (UNITY_PI * Roughness * Roughness * nDoth * nDoth * nDoth * nDoth);
            }

            float SmithMaskBeckmann (float3 halfDir, float3 otherDir, float roughness)
            {
                float hDoto = max(0.001f, DotClamped(halfDir, otherDir));
                float a = hDoto / (roughness * sqrt(1 - hDoto * hDoto));

                float a2 = a * a;
                return a < 1.6f ? (1.0f - 1.259f * a + 0.396f * a2) / (3.535f * a + 2.181 * a2) : 0.0f;
            }

            float ComputeExpFogFactor(float depth, float density)
            {
                return saturate(pow(1.0 - exp(-depth * density), _FogPower));
            }

            float4 frag(g2f i) : SV_TARGET
            {
                float3 worldPos = i.data.worldPos;
                float3 worldNormal = i.data.worldNormal;
                float4 clipPos = i.data.pos;
                float clipDepth = i.data.clipDepth;
                float viewDepth = i.data.viewDepth;
                float2 screenUV = i.data.screenUV;

                float4 shadowCoord = mul(unity_WorldToShadow[0], float4(worldPos, 1));
                shadowCoord.xyz /= shadowCoord.w;

                fixed shadow = SHADOW_ATTENUATION(i);
                
                float screenDepth = DecodeFloatRG(tex2D(_CameraDepthNormalsTexture, screenUV).zw);
                float depthDiff =  screenDepth - viewDepth;
                float intersect = 0;
                if(depthDiff > 0){
                    intersect = 1 - smoothstep(0, _ProjectionParams.w, depthDiff);
                }
            
                float4 displacementFoam0 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(worldPos.xz * _Tile0, 0), 0) * _LayerContribute0;
                float4 displacementFoam1 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(worldPos.xz * _Tile1, 1), 0) * _LayerContribute1;
                float4 displacementFoam2 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(worldPos.xz * _Tile2, 2), 0) * _LayerContribute2;
                float4 displacementFoam3 = UNITY_SAMPLE_TEX2DARRAY_LOD(_DisplacementTexture, float3(worldPos.xz * _Tile3, 3), 0) * _LayerContribute3;
                float4 displacementFoam = displacementFoam0 + displacementFoam1 + displacementFoam2 + displacementFoam3;

                float foam = lerp(0.0f, saturate(displacementFoam.a), pow(clipDepth, _FoamDepthAttenuation));
                foam = foam + intersect * pow(foam, _EdgeFoamPower);
                foam *= saturate(shadow + _ShadowIntensity);

                float2 slope0 = UNITY_SAMPLE_TEX2DARRAY_LOD(_SlopeTexture, float3(i.data.uv * _Tile0, 0), 0) * _LayerContribute0;
                float2 slope1 = UNITY_SAMPLE_TEX2DARRAY_LOD(_SlopeTexture, float3(i.data.uv * _Tile1, 1), 0) * _LayerContribute1;
                float2 slope2 = UNITY_SAMPLE_TEX2DARRAY_LOD(_SlopeTexture, float3(i.data.uv * _Tile2, 2), 0) * _LayerContribute2;
                float2 slope3 = UNITY_SAMPLE_TEX2DARRAY_LOD(_SlopeTexture, float3(i.data.uv * _Tile3, 3), 0) * _LayerContribute3;
                float2 slopeMixA = slope0 + slope1 + slope2 + slope3;
                float2 slopeMixB = slope2 + slope3;

                float inverseUVDepth = saturate(pow(length(i.data.uv / 500 * _VarMaskRange), _VarMaskPower));
                float normalVarMask = UNITY_SAMPLE_TEX2D(_VariationMask, float2(i.data.uv / 1000 * _VarMaskTexScale)).r * inverseUVDepth;
                normalVarMask = saturate(normalVarMask * 4);

                float2 finalSlope = lerp(slopeMixA, slopeMixB, normalVarMask) * _NormalStrength;

                //宏观法线和中观法线，可以理解为整体法线和细节法线
                float3 macroNormal = float3(0.0, 1.0, 0.0);
                float3 mesoNormal = normalize(float3(-finalSlope.x, 1.0, -finalSlope.y));
                mesoNormal = lerp(macroNormal, mesoNormal, pow(saturate(clipDepth), _DisplaceDepthAttenuation));
                mesoNormal = normalize(UnityObjectToWorldNormal(mesoNormal));

                //在片元着色器中计算精度更高，适合水面效果
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - worldPos);
                float3 halfDir = normalize(lightDir + viewDir);
                float3 reflectDir = reflect(-viewDir, mesoNormal);
                float3 lightColor = _LightColor0.rgb;

                float roughness = _Roughness + foam * _FoamRoughness;
                float viewMask = SmithMaskBeckmann(halfDir, viewDir, roughness);
				float lightMask = SmithMaskBeckmann(halfDir, lightDir, roughness);
                float geometryMask = rcp(1 + viewMask + lightMask);

                float nDotl = max(0.001f, DotClamped(mesoNormal, lightDir));
                float nDoth = max(0.001, DotClamped(mesoNormal, halfDir));

                float eta = 1.33f;
                float reflecRate = (eta - 1) * (eta - 1) / (eta + 1) /(eta + 1);

                float numerator = pow(1 - dot(mesoNormal, viewDir), 5 * exp(-2.69 * roughness));
                float fresnel = saturate(reflecRate + (1 - reflecRate) * numerator / (1.0f + 22.7f * pow(roughness, 1.5f)));

                float3 specular = lightColor * fresnel * geometryMask * Beckmann(nDoth, roughness);
                specular /= 4.0f * max(0.001f, DotClamped(macroNormal, lightDir));
                specular *= DotClamped(mesoNormal, lightDir);
                specular *= shadow;
                
                float var_H = max(0.0f, displacementFoam0.y) * _HeightStrength;

                float k1 = _WavePeakScatterStrength * var_H * pow(DotClamped(lightDir, -viewDir), 4.0f) * pow(0.5f - 0.5f * dot(lightDir, mesoNormal), 3.0f);
                k1 = lerp(0.0f, k1, pow(saturate(clipDepth), _DisplaceDepthAttenuation));
                float k2 = _ScatterStrength * pow(DotClamped(viewDir, mesoNormal), 2.0f);
                float k3 = _ScatterShadowStrength * nDotl;
                float k4 = _AmbientDensity;

                float3 ambientColor = ShadeSH9(float4(worldNormal, 1.0));
                half3 envReflect = DecodeHDR(UNITY_SAMPLE_TEXCUBE(unity_SpecCube0, reflectDir), unity_SpecCube0_HDR);
                envReflect *= _EnvirLightStrength;
                envReflect *= saturate(shadow + _ShadowIntensity + 0.5);

                float3 scatter = (k1 * _ScatterPeakColor + k2 * _ScatterColor) * lightColor * rcp(1 + lightMask) * saturate(shadow + _ShadowIntensity);
                scatter += k3 * _ScatterColor * lightColor * saturate(shadow + _ShadowIntensity);
                scatter += k4 * ambientColor;

                float fog = ComputeExpFogFactor(viewDepth, _FogDensity);

                float3 output = ((1.0f - fresnel) * scatter) + specular + fresnel * envReflect;
                output = lerp(output, _FoamColor * lightColor, saturate(foam));
                output = lerp(output, _FogColor, fog);

                return float4(output, 1);
            }

            ENDCG
        }

    }
    FallBack "Specular"
}
