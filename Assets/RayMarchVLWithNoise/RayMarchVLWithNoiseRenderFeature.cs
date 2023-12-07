using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using TMPro;
using UnityEngine;
using UnityEngine.PlayerLoop;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Text.RegularExpressions;
using UnityEngine.Windows;
using Random = UnityEngine.Random;

public class RayMarchVLWithNoiseRenderFeature : ScriptableRendererFeature
{
    [System.Serializable]
    public class RenderPassSettings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        
        // Used for any potential down-sampling we will do in the pass.
        [Range(1,4)] public int downsample = 1;
        public Material material;
        public Shader shader;
        public string textureBundlePath = "Assets/RayMarchVLWithNoise/Resources/64_64/";
        public string resourcesPath = "64_64/";
        public string regPattern = "HDR_L_";
        public int textureBundleCount = 64;
    }
    
    public class TextureList
    {
        public Texture m_CustomRenderTexture;
    } 
    
    GrabTextureColorPass m_ScriptablePass;
    public RenderPassSettings m_PassSettings = new RenderPassSettings();
    public static TextureList m_TextureList = new TextureList();

    
    /// <inheritdoc/>
    public override void Create()
    {
        this.name = "Volumetric Lighting";
        m_ScriptablePass = new GrabTextureColorPass(m_PassSettings);
    }
    
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_PassSettings.shader == null)
        {
            Debug.Log("[VolumetricLightRenderFeature] No shader selected, skip this pass.");
            return;
        }

        if (m_PassSettings.material == null)
        {
            m_PassSettings.material = CoreUtils.CreateEngineMaterial(m_PassSettings.shader);
        }
        
        renderer.EnqueuePass(m_ScriptablePass);
    }
    
    class GrabTextureColorPass : ScriptableRenderPass
    {
        /**************************************** Render Pass Properties *******************************************/
        /***********************************************************************************************************/
        private const string s_ProfilerTag = "Volumetric Lighting Pass";
        private RayMarchVLWithNoiseRenderFeature.RenderPassSettings m_PassSetting;
        private Material m_Material;
        private Texture2D m_noiseMap;
        private List<Texture2D> m_textureBundle;
        private RenderTargetIdentifier m_ColorBuffer;
        private RayMarchVLWithNoiseVolumeComponent m_RayMarchVlWithNoiseVolumeComponent;
        
        // We use s_RenderTargetName to get the propertyID and creates a temporary render texture
        private const string s_RenderTargetNameTemp01 = "_TemporaryBuffer01";
        private const string s_RenderTargetNameTemp02 = "_TemporaryBuffer02";
        private RenderTargetHandle m_VolumetricLightRTHandle;
        private RenderTargetHandle m_GaussianRTHandle;
        /***********************************************************************************************************/

        public GrabTextureColorPass(RenderPassSettings passSettings)
        {
            m_RayMarchVlWithNoiseVolumeComponent = VolumeManager.instance.stack.GetComponent<RayMarchVLWithNoiseVolumeComponent>();
            this.m_PassSetting = passSettings;

            // Set the render pass event.
            renderPassEvent = passSettings.renderPassEvent; 
            if (passSettings.material == null)
            {
                Debug.Log("[VolumetricLightRenderFeature] No material selected");
            }
            else
            {
                m_Material = passSettings.material;
                
                
                List<string> returnList = new List<string>();
                GetFileNameWithRegular(returnList, m_PassSetting.textureBundlePath, m_PassSetting.regPattern);
                m_textureBundle = new List<Texture2D>();
                
                foreach (var fileName in returnList)
                {
                    // Debug.Log(m_PassSetting.resourcesPath + fileName);
                    Texture2D tempTexture = Resources.Load(m_PassSetting.resourcesPath + fileName) as Texture2D;
                    tempTexture.wrapMode = TextureWrapMode.Repeat;
                    m_textureBundle.Add(tempTexture);
                }
                // Set any material properties based on our pass settings. 
                // m_Material.SetInt(BlurStrengthProperty, passSettings.blurStrength);
            }
        }

        public void GetFileNameWithRegular(List<string> returnList, string fatherFoldName, string regularPattern)
        {
            DirectoryInfo dir = new DirectoryInfo(fatherFoldName);
            Regex regex = new Regex(regularPattern);
            Regex splitRregex = new Regex(".");
            var fileNames = dir.GetFiles("*.png");
            foreach (var fileName in fileNames)
            {
                if (regex.IsMatch(fileName.Name))
                {

                    var nameWithOutExt = fileName.Name.Split(".")[0];
                    returnList.Add(nameWithOutExt);
                }
            }
        }
        
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            // Grab the color buffer from the renderer camera color target.
            m_ColorBuffer = renderingData.cameraData.renderer.cameraColorTarget;
            
            // Grab the camera target descriptor. We will use this when creating a temporary render texture.
            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;
            
            // DownSample the original camera target descriptor. 
            // You would do this for performance reasons or less commonly, for aesthetics.
            descriptor.width /= m_PassSetting.downsample;
            descriptor.height /= m_PassSetting.downsample;
            
            // Set the number of depth bits we need for our temporary render texture.
            descriptor.depthBufferBits = 0;
            descriptor.colorFormat = RenderTextureFormat.DefaultHDR;

            // Create a temporary render texture using the descriptor from above.
            // Init Handle, this will get the ID.
            m_VolumetricLightRTHandle.Init(s_RenderTargetNameTemp01);  
            m_GaussianRTHandle.Init(s_RenderTargetNameTemp02); 
            // Then record a command to create a RT by the ID, this will used to get RTid later.
            cmd.GetTemporaryRT(m_VolumetricLightRTHandle.id, descriptor, FilterMode.Bilinear);
            cmd.GetTemporaryRT(m_GaussianRTHandle.id, descriptor, FilterMode.Bilinear);
        }
        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            m_RayMarchVlWithNoiseVolumeComponent = VolumeManager.instance.stack.GetComponent<RayMarchVLWithNoiseVolumeComponent>();
            var cmd = CommandBufferPool.Get();

            Render(cmd, ref renderingData);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        /*
         * Set only volumetric Lighting param here
         */
        private void SetMaterial()
        {
            m_Material.SetInt("_MaxStep", m_RayMarchVlWithNoiseVolumeComponent.maxStep.value);
            m_Material.SetFloat("_MaxDistance", m_RayMarchVlWithNoiseVolumeComponent.maxDistance.value);
            m_Material.SetFloat("_StepDistance", m_RayMarchVlWithNoiseVolumeComponent.stepDistance.value);
            m_Material.SetFloat("_LightIntensityPerStep", m_RayMarchVlWithNoiseVolumeComponent.lightIntensityPerStep.value);
            m_Material.SetColor("_LightColor", m_RayMarchVlWithNoiseVolumeComponent.lightColor.value);
            m_Material.SetFloat("_NoiseMixFactor", m_RayMarchVlWithNoiseVolumeComponent.noiseMixFactor.value);
            m_Material.SetFloat("_TexArraySliceRange",  Random.Range(0, m_RayMarchVlWithNoiseVolumeComponent.maxSliceCount.value));
            
            int randomIdx = Random.Range(0, m_textureBundle.Count);
            m_noiseMap = m_textureBundle[randomIdx < m_textureBundle.Count ? randomIdx : m_textureBundle.Count - 1];
            m_Material.SetTexture("_NoiseTex", m_noiseMap);
        }
        private void Render(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
            // Volume is activated and camera is not scene camera
            if (m_RayMarchVlWithNoiseVolumeComponent.IsActive() && !renderingData.cameraData.isSceneViewCamera)
            {
                SetMaterial();
                using (new ProfilingScope(cmd, new ProfilingSampler(s_ProfilerTag)))
                {
                    // Volumetric Light pass
                    cmd.Blit(m_ColorBuffer, m_VolumetricLightRTHandle.Identifier(), m_Material, 0);
                    cmd.Blit(m_VolumetricLightRTHandle.Identifier(), m_ColorBuffer);
                    
                    // // loop of Gaussian Blur
                    // for (int i = 0; i < m_RayMarchVlWithNoiseVolumeComponent.blurLoopTime.value; i++)
                    // {
                    //     cmd.Blit(m_VolumetricLightRTHandle.Identifier(), m_GaussianRTHandle.Identifier(), m_Material, 1);
                    //     cmd.Blit(m_GaussianRTHandle.Identifier(), m_VolumetricLightRTHandle.Identifier());
                    // }
                    // cmd.SetGlobalTexture("_BlurVLTex", m_VolumetricLightRTHandle.Identifier());
                    // cmd.Blit(m_VolumetricLightRTHandle.Identifier(), m_GaussianRTHandle.Identifier(), m_Material, 2);
                    // cmd.Blit(m_GaussianRTHandle.Identifier(), m_ColorBuffer);
                }
            }
        }
        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null) throw new ArgumentNullException(nameof(cmd));
            
            // Since we created a temporary render texture in OnCameraSetup, we need to release the memory here to avoid a leak.
            cmd.ReleaseTemporaryRT(m_VolumetricLightRTHandle.id);
            cmd.ReleaseTemporaryRT(m_GaussianRTHandle.id);
        }
    }
}


