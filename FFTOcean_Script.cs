using System;
using System.Collections;
using System.Collections.Generic;
using static System.Runtime.InteropServices.Marshal;
using UnityEngine;
using UnityEngine.Rendering;
using Unity.Mathematics;

[RequireComponent (typeof(MeshFilter), typeof(MeshRenderer))]

public class FFTOcean_Script : MonoBehaviour
{

    //声明全部贴图
    public RenderTexture InitialSpectrumTexture,
                         SpectrumTexture,
                         DisplacementTexture,
                         SlopeTexture,
                         BuoyancyData,
                         VariationMask;
    [Header("Shaders")]
    public ComputeShader FFTComputeShader;
    public Shader FFTWaterShader;


    [Header("Water Surface Mesh Setting")]

    public int waterMeshLength = 200;
    public int waterMeshRes = 10;

    [Range(10, 20)]
    public int TessEdgeLength = 16;
    private Mesh waterSurface;
    private Material waterMaterial;
    private int Resolusion, threadGroupsX, threadGroupsY;


    [Header("General Settings")]
    public float DisplaceDepthAttenuation = 10;

    public float FoamDepthAttenuation = 20;

    [Range(0.0f, 5.0f)]
    public float Speed = 0.5f;
    public int Seed = 28;
    [Range(2.0f, 20.0f)]
    public float Gravity = 9.81f;

    private float Depth = 10.0f;
    private float RepeatTime = 200.0f;
    private float LowCutOff = 0.0001f;
    private float HighCutOff = 9000.0f;


    [Header("Layer 01")]
    [Range(0.0f, 1.0f)]
    public float LayerContribute0 = 0.8f;
    [Range(0.0f, 0.25f)]
    public float Tile0 = 0.04f;

    [SerializeField]
    public JONSWAP_DisplaySettings DisplaySpectrum0;
    [SerializeField]
    public JONSWAP_DisplaySettings DisplaySpectrum1;

    private int LengthScale0 = 4;


    [Header("Layer 02")]
    [Range(0.0f, 1.0f)]
    public float LayerContribute1 = 0.8f;

    [Range(0.0f, 0.25f)]
    public float Tile1 = 0.06f;

    [SerializeField]
    public JONSWAP_DisplaySettings DisplaySpectrum2;
    public JONSWAP_DisplaySettings DisplaySpectrum3;
    private int LengthScale1 = 4;


    [Header("Layer 03")]
    [Range(0.0f, 1.0f)]
    public float LayerContribute2 = 0.6f;

    [Range(0.0f, 0.25f)]
    public float Tile2 = 0.12f;

    [SerializeField]
    public JONSWAP_DisplaySettings DisplaySpectrum4;
    public JONSWAP_DisplaySettings DisplaySpectrum5;
    private int LengthScale2 = 4;


    [Header("Layer 04")]
    [Range(0.0f, 1.0f)]
    public float LayerContribute3 = 0.4f;

    [Range(0.0f, 0.25f)]
    public float Tile3 = 0.18f;

    [SerializeField]
    public JONSWAP_DisplaySettings DisplaySpectrum6;
    public JONSWAP_DisplaySettings DisplaySpectrum7;
    private int LengthScale3 = 4;


    [Header("Shader Settings")]
    public Color ScatterColor = new Color(0.0f, 0.67f, 1.0f, 1.0f);
    public Color ScatterPeakColor = new Color(0.0f, 0.67f, 1.0f, 1.0f);
    public float WavePeakScatterStrength = 2.0f;
    public float ScatterStrength = 0.1f;
    public float ScatterShadowStrength = 0.1f;
    [Space(10)]

    public float AmbientDensity = 0.2f;
    public float EnvirReflectStrength = 1.0f;
    [Space(10)]
    public float FoamRoughness = 0.2f;
    public float Roughness = 0.1f;
    [Space(10)]
    public float NormalStrength = 0.2f;

    public float HeightStrength = 1.0f;

    [Space(10)]
    [Range(0.0f, 1.0f)]
    public float ShadowIntensity = 0.2f;


    [Header("Foam Settings")]
    public Color FoamColor = new Color(1, 1, 1, 1);
    [Space(10)]
    public Vector2 WaveSharp = new Vector2(0.4f, 0.4f);
    [Range(-1.0f, 1.0f)]
    public float FoamBias = 0.2f;

    [Range(-0.0f, 4.0f)]
    public float FoamPower = 1.5f;

    [Range(0.0f, 1.0f)]
    public float FoamAdd =0.1f;

    [Range(0.0f, 1.0f)]
    public float FoamDecayRate = 0.05f;
    [Range(0.01f, 1.0f)]
    public float EdgeFoamPower;

    [Header("Normal Variation")]
    [Range(0.01f, 10.0f)]
    public float VarMaskRange = 3.0f;
    [Range(0.01f, 10.0f)]
    public float VarMaskPower = 3.0f;
    [Range(0.01f, 10.0f)]
    public float VarMaskTexScale = 2.0f;

    [Header("Fog Settings")]
    public Color FogColor = new Color(0.5f, 0.75f, 0.0f);

    [Range(0.0f, 20.0f)]
    public float FogDensity = 1.0f;
    [Range(0.0f, 10.0f)]
    public float FogPower = 4.0f;


    [System.Serializable]
    //传递到compute shader中的结构体
    public struct JONSWAP_ComputeSettings
    {
        public float scale;
        public float angle;
        public float spreadBlend;
        public float swell;
        public float alpha;
        public float peakOmega;
        public float gamma;
        public float shortWavesFade;
    }
    JONSWAP_ComputeSettings[] ComputeSpectrums = new JONSWAP_ComputeSettings[8];

    //开放的结构体参数 用windSpeed和windDirection动态计算alpha和peakOmega angle和gamma为了更好理解改了名称
    [System.Serializable]
    public struct JONSWAP_DisplaySettings
    {
        [Range(0, 5)]
        public float scale;
        public float windSpeed;

        [Range(0, 360)]
        public float windDirection;
        public float fetch;
        [Range(0, 1)]
        public float spreadBlend;
        [Range(0, 1)]
        public float swell;
        public float peakEnhancement;

        [Range(0, 1)]
        public float shortWavesFade;
    }

    //JONSWAP结构体的Buffer
    private ComputeBuffer JonswapBuffer;

    //声明全部核心函数
    private int CS_InitializeSpectrum;
    private int CS_PackSpectrumConjugate;
    private int CS_UpdateSpectrum;
    private int CS_HorizontalIFFT;
    private int CS_VerticalIFFT;
    private int CS_AssembleTextures;


    public RenderTexture GetBuoyancyData()
    {
        return BuoyancyData;
    }

    //设置默认值
    private void Reset()
    {
        //00
        DisplaySpectrum0.scale = 0.4f;
        DisplaySpectrum0.windSpeed = 1200.0f;
        DisplaySpectrum0.windDirection = 130.0f;
        DisplaySpectrum0.fetch = 600.0f;
        DisplaySpectrum0.spreadBlend = 1.0f;
        DisplaySpectrum0.swell = 0.9f;
        DisplaySpectrum0.peakEnhancement = 5.0f;
        DisplaySpectrum0.shortWavesFade = 0.8f;
        //01
        DisplaySpectrum1.scale = 0.4f;
        DisplaySpectrum1.windSpeed = 1000.0f;
        DisplaySpectrum0.windDirection = 50.0f;
        DisplaySpectrum1.fetch = 500.0f;
        DisplaySpectrum1.spreadBlend = 1.0f;
        DisplaySpectrum1.swell = 0.9f;
        DisplaySpectrum1.peakEnhancement = 5.0f;
        DisplaySpectrum1.shortWavesFade = 0.8f;


        //02
        DisplaySpectrum2.scale = 0.1f;
        DisplaySpectrum2.windSpeed = 800.0f;
        DisplaySpectrum2.windDirection = 45.0f;
        DisplaySpectrum2.fetch = 400.0f;
        DisplaySpectrum2.spreadBlend = 0.98f;
        DisplaySpectrum2.swell = 0.9f;
        DisplaySpectrum2.peakEnhancement = 5.0f;
        DisplaySpectrum2.shortWavesFade = 0.4f;
        //03
        DisplaySpectrum3.scale = 0.1f;
        DisplaySpectrum3.windSpeed = 800.0f;
        DisplaySpectrum3.windDirection = 135.0f;
        DisplaySpectrum3.fetch = 350.0f;
        DisplaySpectrum3.spreadBlend = 0.98f;
        DisplaySpectrum3.swell = 0.9f;
        DisplaySpectrum3.peakEnhancement = 5.0f;
        DisplaySpectrum3.shortWavesFade = 0.4f;


        //04
        DisplaySpectrum4.scale = 0.04f;
        DisplaySpectrum4.windSpeed = 100.0f;
        DisplaySpectrum4.windDirection = 260.0f;
        DisplaySpectrum4.fetch = 100.0f;
        DisplaySpectrum4.spreadBlend = 0.95f;
        DisplaySpectrum4.swell = 0.8f;
        DisplaySpectrum4.peakEnhancement = 3.0f;
        DisplaySpectrum4.shortWavesFade = 0.4f;
        //05
        DisplaySpectrum5.scale = 0.04f;
        DisplaySpectrum5.windSpeed = 50.0f;
        DisplaySpectrum5.windDirection = 280.0f;
        DisplaySpectrum5.fetch = 100.0f;
        DisplaySpectrum5.spreadBlend = 0.95f;
        DisplaySpectrum5.swell = 0.8f;
        DisplaySpectrum5.peakEnhancement = 3.0f;
        DisplaySpectrum5.shortWavesFade = 0.4f;


        //06
        DisplaySpectrum6.scale = 0.1f;
        DisplaySpectrum6.windSpeed = 10.0f;
        DisplaySpectrum6.windDirection = 0.0f;
        DisplaySpectrum6.fetch = 40.0f;
        DisplaySpectrum6.spreadBlend = 0.8f;
        DisplaySpectrum6.swell = 0.6f;
        DisplaySpectrum6.peakEnhancement = 1.0f;
        DisplaySpectrum6.shortWavesFade = 0.2f;
        //07
        DisplaySpectrum7.scale = 0.1f;
        DisplaySpectrum7.windSpeed = 10.0f;
        DisplaySpectrum7.windDirection = 0.0f;
        DisplaySpectrum7.fetch = 20.0f;
        DisplaySpectrum7.spreadBlend = 0.6f;
        DisplaySpectrum7.swell = 0.4f;
        DisplaySpectrum7.peakEnhancement = 1.0f;
        DisplaySpectrum7.shortWavesFade = 0.2f;
    }

    //生成水面mesh
    private void CreateWaterSurface()
    {
        GetComponent<MeshFilter>().mesh = waterSurface = new Mesh();
        waterSurface.name = "Water Surface";
        waterSurface.indexFormat = IndexFormat.UInt32;

        float halfLength = waterMeshLength / 2.0f;
        int sideVertCount = waterMeshLength * waterMeshRes / 100;

        Vector3[] vertices = new Vector3[(sideVertCount + 1) * (sideVertCount + 1)];
        Vector2[] uv = new Vector2[vertices.Length];
        Vector4[] tangents = new Vector4[vertices.Length];
        Vector4 tangent = new Vector4(1f, 0f, 0f, -1f);
        int[] triangles = new int[sideVertCount * sideVertCount * 6];

        //为顶点，uv，切线赋值
        for (int i = 0, x = 0; x <= sideVertCount; ++x)
        {
            for (int z = 0; z <= sideVertCount; ++z, ++i)
            {
                vertices[i] = new Vector3(((float)x / sideVertCount * waterMeshLength) - halfLength,
                                            0,
                                            ((float)z / sideVertCount * waterMeshLength) - halfLength);
                uv[i] = new Vector2((float)x / sideVertCount, (float)z / sideVertCount);
                tangents[i] = tangent;
            }
        }

        //为三角形赋值
        for (int triIndex = 0, verIndex = 0, x = 0; x < sideVertCount; ++verIndex, ++x)
        {
            for (int z = 0; z < sideVertCount; triIndex += 6, ++verIndex, ++z)
            {
                triangles[triIndex] = verIndex;
                triangles[triIndex + 1] = verIndex + 1;
                triangles[triIndex + 2] = verIndex + sideVertCount + 2;
                triangles[triIndex + 3] = verIndex;
                triangles[triIndex + 4] = verIndex + sideVertCount + 2;
                triangles[triIndex + 5] = verIndex + sideVertCount + 1;
            }
        }

        waterSurface.vertices = vertices;
        waterSurface.uv = uv;
        waterSurface.tangents = tangents;
        waterSurface.triangles = triangles;
        waterSurface.RecalculateNormals();
        Vector3[] normals = waterSurface.normals;
    }

    private void CreateWaterMaterial()
    {
        if (FFTWaterShader == null) return;

        waterMaterial = new Material(FFTWaterShader);

        MeshRenderer renderer = GetComponent<MeshRenderer>();

        renderer.material = waterMaterial;
    }

    //———————————————————————————————————————————————————————————————————————
    //功能函数

    //Alpha数据转化函数
    float JonswapAlpha(float fetch, float windSpeed)
    {
        return 0.076f * Mathf.Pow(Gravity * fetch / windSpeed / windSpeed, -0.22f); //通过fetch和windSpeed来动态计算Alpha （需要寻找参考）
    }

    //PeakOmega数据转化函数
    float JonswapPeakFrequency(float fetch, float windSpeed)
    {
        return 22 * Mathf.Pow(windSpeed * fetch / Gravity / Gravity, -0.33f); //通过fetch和windSpeed来动态计算peakOmega （需要寻找参考）
    }

    //将用户数据传递到结构体中
    void FillSpectrumStruct(JONSWAP_DisplaySettings displaySettings, ref JONSWAP_ComputeSettings computeSettings)
    {
        computeSettings.scale = displaySettings.scale;
        computeSettings.angle = displaySettings.windDirection / 180 * Mathf.PI;
        computeSettings.spreadBlend = displaySettings.spreadBlend;
        computeSettings.swell = Mathf.Clamp(displaySettings.swell, 0.01f, 1);
        computeSettings.alpha = JonswapAlpha(displaySettings.fetch, displaySettings.windSpeed);
        computeSettings.peakOmega = JonswapPeakFrequency(displaySettings.fetch, displaySettings.windSpeed);
        computeSettings.gamma = displaySettings.peakEnhancement;
        computeSettings.shortWavesFade = displaySettings.shortWavesFade;
    }

    //创建缓冲区并将数据传递到缓冲区
    void SetSpectrumBuffers()
    {
        FillSpectrumStruct(DisplaySpectrum0, ref ComputeSpectrums[0]);
        FillSpectrumStruct(DisplaySpectrum1, ref ComputeSpectrums[1]);
        FillSpectrumStruct(DisplaySpectrum2, ref ComputeSpectrums[2]);
        FillSpectrumStruct(DisplaySpectrum3, ref ComputeSpectrums[3]);
        FillSpectrumStruct(DisplaySpectrum4, ref ComputeSpectrums[4]);
        FillSpectrumStruct(DisplaySpectrum5, ref ComputeSpectrums[5]);
        FillSpectrumStruct(DisplaySpectrum6, ref ComputeSpectrums[6]);
        FillSpectrumStruct(DisplaySpectrum7, ref ComputeSpectrums[7]);

        JonswapBuffer.SetData(ComputeSpectrums);
        FFTComputeShader.SetBuffer(0, "_JonswapParameters", JonswapBuffer);
    }

    //创建并设置贴图
    RenderTexture CreateRenderTexArray(int width, int height, int depth, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.dimension = UnityEngine.Rendering.TextureDimension.Tex2DArray;
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.volumeDepth = depth;
        rt.useMipMap = useMips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 16;
        rt.Create();

        return rt;
    }

    RenderTexture CreateRenderTex(int width, int height, RenderTextureFormat format, bool useMips)
    {
        RenderTexture rt = new RenderTexture(width, height, 0, format, RenderTextureReadWrite.Linear);
        rt.filterMode = FilterMode.Bilinear;
        rt.wrapMode = TextureWrapMode.Repeat;
        rt.enableRandomWrite = true;
        rt.useMipMap = useMips;
        rt.autoGenerateMips = false;
        rt.anisoLevel = 16;
        rt.Create();

        return rt;
    }

    void SetCompParam()
    {
        FFTComputeShader.SetFloat("_Depth", Depth);
        FFTComputeShader.SetFloat("_Gravity", Gravity);
        FFTComputeShader.SetFloat("_FrameTime", Time.time * Speed);
        FFTComputeShader.SetFloat("_RepeatTime", RepeatTime);
        FFTComputeShader.SetFloat("_LowCutOff", LowCutOff);
        FFTComputeShader.SetFloat("_HighCutOff", HighCutOff);
        FFTComputeShader.SetVector("_WaveSharp", WaveSharp);

        FFTComputeShader.SetInt("_Resolution", Resolusion);
        FFTComputeShader.SetInt("_LengthScale0", LengthScale0);
        FFTComputeShader.SetInt("_LengthScale1", LengthScale1);
        FFTComputeShader.SetInt("_LengthScale2", LengthScale2);
        FFTComputeShader.SetInt("_LengthScale3", LengthScale3);
        FFTComputeShader.SetInt("_Seed", Seed);

        FFTComputeShader.SetFloat("_FoamBias", FoamBias);
        FFTComputeShader.SetFloat("_FoamPower", FoamPower);
        FFTComputeShader.SetFloat("_FoamAdd", FoamAdd);
        FFTComputeShader.SetFloat("_FoamDecayRate", FoamDecayRate);
    }

    void SetMaterialParam()
    {
        waterMaterial.SetFloat("_DisplaceDepthAttenuation", DisplaceDepthAttenuation);
        waterMaterial.SetFloat("_FoamDepthAttenuation", FoamDepthAttenuation);

        waterMaterial.SetFloat("_TessEdgeLength", TessEdgeLength);
        waterMaterial.SetFloat("_Tile0", Tile0);
        waterMaterial.SetFloat("_Tile1", Tile1);
        waterMaterial.SetFloat("_Tile2", Tile2);
        waterMaterial.SetFloat("_Tile3", Tile3);

        waterMaterial.SetFloat("_LayerContribute0", LayerContribute0);
        waterMaterial.SetFloat("_LayerContribute1", LayerContribute1);
        waterMaterial.SetFloat("_LayerContribute2", LayerContribute2);
        waterMaterial.SetFloat("_LayerContribute3", LayerContribute3);

        waterMaterial.SetFloat("_NormalStrength", NormalStrength);
        waterMaterial.SetFloat("_HeightStrength", HeightStrength);

        waterMaterial.SetColor("_ScatterColor", ScatterColor);
        waterMaterial.SetColor("_ScatterPeakColor", ScatterPeakColor);
        waterMaterial.SetColor("_FoamColor", FoamColor);

        waterMaterial.SetFloat("_AmbientDensity", AmbientDensity);

        waterMaterial.SetFloat("_WavePeakScatterStrength", WavePeakScatterStrength);
        waterMaterial.SetFloat("_ScatterStrength", ScatterStrength);
        waterMaterial.SetFloat("_ScatterShadowStrength", ScatterShadowStrength);

        waterMaterial.SetFloat("_FoamRoughness", FoamRoughness);
        waterMaterial.SetFloat("_Roughness", Roughness);
        waterMaterial.SetFloat("_EnvirLightStrength", EnvirReflectStrength);

        waterMaterial.SetFloat("_EdgeFoamPower", EdgeFoamPower);
        waterMaterial.SetFloat("_ShadowIntensity", ShadowIntensity);

        waterMaterial.SetFloat("_VarMaskRange", VarMaskRange);
        waterMaterial.SetFloat("_VarMaskPower", VarMaskPower);
        waterMaterial.SetFloat("_VarMaskTexScale", VarMaskTexScale);

        waterMaterial.SetFloat("_FogDensity", FogDensity); 
        waterMaterial.SetFloat("_FogPower", FogPower); 
        waterMaterial.SetColor("_FogColor", FogColor);
    }

    void OnEnable()
    {
        CreateWaterSurface();
        CreateWaterMaterial();

        //Private参数赋值
        Resolusion = 1024;
        threadGroupsX = Mathf.CeilToInt(Resolusion / 8.0f);
        threadGroupsY = Mathf.CeilToInt(Resolusion / 8.0f);

        //调用ComputeShader核心函数
        CS_InitializeSpectrum = FFTComputeShader.FindKernel("CS_InitializeSpectrum");
        CS_PackSpectrumConjugate = FFTComputeShader.FindKernel("CS_PackSpectrumConjugate");
        CS_UpdateSpectrum = FFTComputeShader.FindKernel("CS_UpdateSpectrum");
        CS_HorizontalIFFT = FFTComputeShader.FindKernel("CS_HorizontalIFFT");
        CS_VerticalIFFT = FFTComputeShader.FindKernel("CS_VerticalIFFT");
        CS_AssembleTextures = FFTComputeShader.FindKernel("CS_AssembleTextures");

        //创建贴图
        InitialSpectrumTexture = CreateRenderTexArray(Resolusion, Resolusion, 4, RenderTextureFormat.ARGBHalf, true);
        SpectrumTexture = CreateRenderTexArray(Resolusion, Resolusion, 8, RenderTextureFormat.ARGBHalf, true);
        DisplacementTexture = CreateRenderTexArray(Resolusion, Resolusion, 4, RenderTextureFormat.ARGBHalf, true);
        SlopeTexture = CreateRenderTexArray(Resolusion, Resolusion, 4, RenderTextureFormat.RGHalf, true);
        BuoyancyData = CreateRenderTex(Resolusion, Resolusion, RenderTextureFormat.RHalf, false);
        VariationMask = CreateRenderTex(Resolusion, Resolusion, RenderTextureFormat.ARGBHalf, false);

        InitialSpectrumTexture.Create();
        SpectrumTexture.Create();

        //传递JONSWAP结构体数据
        JonswapBuffer = new ComputeBuffer(8, 8 * sizeof(float));
        SetSpectrumBuffers();

        //赋值
        SetCompParam();
    }

    void Update()
    {
        //赋值
        SetCompParam();
        SetSpectrumBuffers();
        SetMaterialParam();

        //初始化频谱
        FFTComputeShader.SetTexture(CS_InitializeSpectrum, "_InitialSpectrumTexture", InitialSpectrumTexture);
        FFTComputeShader.Dispatch(CS_InitializeSpectrum, threadGroupsX, threadGroupsY, 1);

        //共轭
        FFTComputeShader.SetTexture(CS_PackSpectrumConjugate, "_InitialSpectrumTexture", InitialSpectrumTexture);
        FFTComputeShader.Dispatch(CS_PackSpectrumConjugate, threadGroupsX, threadGroupsY, 1);

        //为IFFT更新频谱
        FFTComputeShader.SetTexture(CS_UpdateSpectrum, "_InitialSpectrumTexture", InitialSpectrumTexture);
        FFTComputeShader.SetTexture(CS_UpdateSpectrum, "_SpectrumTexture", SpectrumTexture);
        FFTComputeShader.SetTexture(CS_UpdateSpectrum, "_VariationMask", VariationMask);
        FFTComputeShader.Dispatch(CS_UpdateSpectrum, threadGroupsX, threadGroupsY, 1);


        //海浪IFFT
        FFTComputeShader.SetTexture(CS_HorizontalIFFT, "_FourierTarget", SpectrumTexture);
        FFTComputeShader.SetTexture(CS_HorizontalIFFT, "_FourierTargetExtra", VariationMask);
        FFTComputeShader.Dispatch(CS_HorizontalIFFT, 1, Resolusion, 1);

        FFTComputeShader.SetTexture(CS_VerticalIFFT, "_FourierTarget", SpectrumTexture);
        FFTComputeShader.SetTexture(CS_VerticalIFFT, "_FourierTargetExtra", VariationMask);
        FFTComputeShader.Dispatch(CS_VerticalIFFT, 1, Resolusion, 1);


        //整合贴图
        FFTComputeShader.SetTexture(CS_AssembleTextures, "_SpectrumTexture", SpectrumTexture);
        FFTComputeShader.SetTexture(CS_AssembleTextures, "_DisplacementTexture", DisplacementTexture);
        FFTComputeShader.SetTexture(CS_AssembleTextures, "_SlopeTexture", SlopeTexture);
        FFTComputeShader.SetTexture(CS_AssembleTextures, "_BuoyancyData", BuoyancyData);
        FFTComputeShader.SetTexture(CS_AssembleTextures, "_VariationMask", VariationMask);
        FFTComputeShader.Dispatch(CS_AssembleTextures, threadGroupsX, threadGroupsY, 1);

        //将结果传入Shader
        waterMaterial.SetTexture("_DisplacementTexture", DisplacementTexture);
        waterMaterial.SetTexture("_SlopeTexture", SlopeTexture);
        waterMaterial.SetTexture("_VariationMask", VariationMask);
    }

    void OnDestroy()
    {
        if (JonswapBuffer != null)
        {
            JonswapBuffer.Release();
        }
    }
}
