Shader "Custom/RayMarchVolumetricLightingWithNoise"
{
    Properties
    {
        [HideInInspector]_MainTex("Main Texture", 2D) = "white" {}  // This will be screen space texture by default
        _NoiseTex2D("Noise Texture Array", 2DArray) = "white" {}
        _NoiseTex("Noise Texture Array", 2D) = "white" {}
        
//        [Tooltip(中文)]
        _TexArraySliceRange("Texture Array Slice Range", Float) = 6
        _TexArrayUVScale("Texture Array UV Scale", Float) = 1.0
        
        [Range(0, 1)] _NoiseMixFactor("Noise Mix Factor", Float) = 0.1
        _LightColor("_LightColor", color) = (1, 1, 1, 1)
        _MaxStep("Max March Step", float) = 200
        _MaxDistance("Max Distance in world space", float) = 1000
        _StepDistance("Distance of Step", float) = 0.1
        _LightIntensityPerStep("Light Intensity Per Step", float) = 0.01
        _BlurInt("Gaussian Blur intensity", float) = 0.2
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"}
        LOD 0
        Pass // Pass No.0: Volumetric Lighting
        {
            
            ZWrite Off
            ZTest Always
            Cull Off
            
            Name "Volumetric Standard"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _SHADOWS_SOFT
            
            #pragma require 2darray
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            
            TEXTURE2D(_MainTex);        SAMPLER(sampler_MainTex);
            TEXTURE2D(_BlurVLTex);      SAMPLER(sampler_BlurVLTex);
            TEXTURE2D(_NoiseTex);      SAMPLER(sampler_NoiseTex);
            TEXTURE2D_ARRAY(_NoiseTex2D); SAMPLER(sampler_NoiseTex2D);
            
            CBUFFER_START(UnityPerMaterial)
            // float4 _MainTex_ST;
            float4 _LightColor;
            half _NoiseMixFactor;
            half _MaxStep;
            half _LightIntensityPerStep;
            half _MaxDistance;
            half _StepDistance;
            half _TexArraySliceRange;
            half _TexArrayUVScale;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varying
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            /*ReconstructWorldSpacePos, input must be Clip Space position xy;*/
            float3 ReconstructWorldSpacePos(float2 UV)
            {
                // 1. Get screenSpace uv
                float2 screenSpaceUV = UV / _ScaledScreenParams.xy;

                // 2. Get pixel depth
                #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(screenSpaceUV);
                #else
                real depth = lerpUNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(screenSpaceUV));
                #endif

                // 3. Get World pos
                float3 worldPos = ComputeWorldSpacePosition(screenSpaceUV, depth, UNITY_MATRIX_I_VP);
                return worldPos;
            }

            float GetShadow(float3 posWorld)
            {
                return MainLightRealtimeShadow(TransformWorldToShadowCoord(posWorld));
            }

            float floatRemap(float value, float2 oriRange, float2 newRange)
            {
                return (value - oriRange.x) / (oriRange.y - oriRange.x) * (newRange.y - newRange.x);
            }
            
            Varying vert (Attributes input)
            {
                Varying output = (Varying)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }


            half4 frag (Varying input) : SV_Target
            {
                half4 finalColor = 0;
                float3 worldPos = ReconstructWorldSpacePos(input.positionCS.xy);
                
                // ray march dir and pos
                float3 rayDirection = normalize(worldPos - _WorldSpaceCameraPos);
                float3 rayCurrentPos = _WorldSpaceCameraPos;
                float maxDistance = min(length(worldPos - _WorldSpaceCameraPos), _MaxDistance);
                float deltaDistance = 2 * maxDistance / _MaxStep;

                float totalLightIntensity = 0;
                float totalLightMarchDistance = 0;
                float distanceBias = maxDistance / _MaxStep;
                
                UNITY_LOOP
                for(int marchStep = 0; marchStep < _MaxStep; marchStep++)
                {
                    float noiseValue = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, rayCurrentPos.xy).r; // *记得改回来层数
                    float randomOffset = floatRemap(noiseValue, float2(0, 1), float2(0, 1)) * deltaDistance;
                    float jitteredDeltaDistance = lerp(randomOffset * deltaDistance, deltaDistance, _NoiseMixFactor);
                    
                    // jitteredDeltaDistance = deltaDistance;
                    
                    totalLightMarchDistance += jitteredDeltaDistance;
                    if(totalLightMarchDistance + distanceBias >= maxDistance)
                    {
                        break;
                    }
                    rayCurrentPos += jitteredDeltaDistance * rayDirection;
                    //totalLightIntensity += rayCurrentPos.z/30;
                    totalLightIntensity += _LightIntensityPerStep * GetShadow(rayCurrentPos);
                }

                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color * totalLightIntensity * _LightColor.rgb * _LightColor.a;
                half3 originalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).rgb;
                finalColor.rgb = originalColor + lightColor;
                
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }

        Pass // Pass No.1: Blur
        {
            ZWrite Off
            ZTest Always
            Cull Off
            
            Name "Gaussian Blur"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            CBUFFER_START(UnityPerMaterial)
            // float4 _MainTex_ST;
            float _BlurInt;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varying
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };
 
            Varying vert (Attributes input)
            {
                Varying output = (Varying)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 frag (Varying input) : SV_Target
            {
                half4 finalColor = 0;
                float blurRange = _BlurInt / 300;

                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(0.0, 0.0)) * 0.147716f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(blurRange, 0.0)) * 0.118318f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(0.0, -blurRange)) * 0.118318f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(0.0, blurRange)) * 0.118318f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(-blurRange, 0.0)) * 0.118318f;
                
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(blurRange, blurRange)) * 0.0947416f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(-blurRange, -blurRange)) * 0.0947416f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(blurRange, -blurRange)) * 0.0947416f;
                finalColor += SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv + float2(-blurRange, blurRange)) * 0.0947416f;
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }

        Pass // Pass No.2: Image add
        {
            ZWrite Off
            ZTest Always
            Cull Off
            
            Name "Gaussian Blur"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            
            TEXTURE2D(_MainTex);    SAMPLER(sampler_MainTex);
            TEXTURE2D(_BlurVLTex);   SAMPLER(sampler_BlurVLTex);
            CBUFFER_START(UnityPerMaterial)
            // float4 _MainTex_ST;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct Varying
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };
 
            Varying vert (Attributes input)
            {
                Varying output = (Varying)0;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv;
                return output;
            }

            half4 frag (Varying input) : SV_Target
            {
                half4 finalColor = 0;
                half3 originalColor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv).rgb;
                half3 volumetricColor = SAMPLE_TEXTURE2D(_BlurVLTex, sampler_BlurVLTex, input.uv).rgb;
                finalColor.rgb = originalColor + volumetricColor;
                return half4(finalColor.rgb, 1);
            }
            ENDHLSL
        }
    }
}