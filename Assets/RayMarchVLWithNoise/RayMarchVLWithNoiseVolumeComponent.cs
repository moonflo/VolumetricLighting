using System;
using System.Collections.Generic;
// using Unity.Entities;
// using Whiterice;

namespace UnityEngine.Rendering.Universal
{
    [System.Serializable, VolumeComponentMenu("FF/RayMarchVLWithNoiseVolumeComponent")]
    public sealed class RayMarchVLWithNoiseVolumeComponent : VolumeComponent, IPostProcessComponent
    {
        [Tooltip("If enable the effect")] public BoolParameter enableEffect = new BoolParameter(true);

        [Tooltip("灯光颜色")] 
        public ColorParameter lightColor = new ColorParameter(Color.white, true);
        public ClampedFloatParameter lightIntensityPerStep =  new ClampedFloatParameter(0.05f, 0.0f, 2.0f);
        public FloatParameter maxDistance = new FloatParameter(1000);
        public ClampedFloatParameter stepDistance = new ClampedFloatParameter(0.1f, 0.1f, 2.0f);
        public ClampedFloatParameter noiseMixFactor = new ClampedFloatParameter(0.1f, 0.0f, 1.0f);
        public IntParameter maxStep = new IntParameter(200);
        public IntParameter maxSliceCount = new IntParameter(256);
        public Texture2DParameter noiseMap00;

        
        public ClampedIntParameter blurLoopTime = new ClampedIntParameter(3, 1, 10);
        public ClampedFloatParameter BlurIntensity = new ClampedFloatParameter(0.3f, 0.0f, 1.0f);
        public bool IsActive() => enableEffect == true;
        public bool IsTileCompatible() => false;

        void loadImageToTexture()
        {
            Texture2D noiseMap01 = Resources.Load("512_512/LDR_LLL1_0") as Texture2D;
            noiseMap00 = new Texture2DParameter(noiseMap01);
        }
        
        protected override void OnEnable()
        {
            loadImageToTexture();
            base.OnEnable();
            
        }
    }
}
