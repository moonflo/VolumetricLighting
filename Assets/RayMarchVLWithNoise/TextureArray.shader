Shader "Custom/TextureArray"
{
    Properties
    {
        _MainTex ("Albedo Texture", 2DArray) = "white" {}
        _TexArraySliceRange("Texture Array Slice Range", Range(0, 256)) = 256
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 0

        Pass
        {
            ZWrite On
            ZTest Always
            Cull back
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma require 2darray
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            TEXTURE2D_ARRAY(_MainTex);  SAMPLER(sampler_MainTex);
            
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float _TexArraySliceRange;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 uv : TEXCOORD0;
            };

            struct Varying
            {
                float4 positionCS : SV_POSITION;
                float3 uvAndArrayIndex : TEXCOORD0;
            };

            Varying vert(Attributes input)
            {
                Varying output = (Varying)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uvAndArrayIndex.xy = TRANSFORM_TEX(input.uv, _MainTex);
                output.uvAndArrayIndex.z = input.uv.z;
                return output;
            }

            half4 frag(Varying input) : SV_Target
            {
                half4 finalColor = 0;
                half4 mainColor = SAMPLE_TEXTURE2D_ARRAY(
                    _MainTex, sampler_MainTex, input.uvAndArrayIndex.xy, _TexArraySliceRange);
                finalColor.rgb = mainColor.xyz;
                finalColor.a = 1;
                return finalColor;
            }
            
            ENDHLSL
        }
    }
}
