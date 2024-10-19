Shader "Awsaf/NewWater"
{
    Properties
    {
        [Header(Color Properties)]
        _MainTex("Albedo (RGB)", 2D) = "white" {}
        _WaterColor ("WaterColor", Color) = (1,1,1,1)
        _DeepWaterColor("DeepWaterColor", Color) = (1,1,1,1)
        _FogThreshHold("FogThreshHold",FLOAT) = 20
        _FogDesity("FogDesity",Float) = 0.5
        [Space(10)]

        [Header(Foam Properties)]
        _FoamTex("FoamTexture", 2D) = "white" {}
        _FoamThreshHold("FoamThreshHold",FLOAT) = 10
        _FoamTexSpeed("FoamTexSpeed",FLOAT) = 2
        _FoamLinesSpeed("FoamLinesSpeed",FLOAT) = 2
        _FoamLines("FoamLines",FLOAT) = 10
        _FoamIntensity("FoamIntensity",Range(0,1)) = 1
        [Space(10)]

        [Header(Frensel Properties)]
        _FrenselPower("FrenselPower",FLOAT) = 5
        [Space(10)]

        [Header(Refraction Properties)]
        _WaterNormal("WaterNormal", 2D) = "bumb" {}
        _RefractionStrength("RefractionStrength",Float) = 0.5
        _DistortionSpeed("DistortionSpeed",Float) = 0.5
        [Space(10)]

        [Header(Caustic Properties)]
        _CausticTex("CausticTexture", 2D) = "black" {}
        _ParallexRange("ParallexRange",Float)=1
        _CausticSpeed("CausticSpeed",Float) = 1
        _Glossiness ("Smoothness", Range(0,1)) = 0.5

    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue" = "Transparent"}
        blend SrcAlpha OneMinusSrcAlpha
        Zwrite Off
        LOD 200

       GrabPass { "_WaterBackground" }

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Water fullforwardshadows alpha:premul

        // Use shader model 3.0 target, to get nicer looking lighting
        #pragma target 3.0

        sampler2D _MainTex,_FoamTex,_CameraDepthTexture,_WaterBackground,_WaterNormal,_CausticTex;
        float4 _FoamTexture_ST;
        struct Input
        {
            float2 uv_WaterNormal;
            float2 uv_FoamTex;
            float2 uv_MainTex;
            float2 uv_CausticTex;
            float3 worldPos;
            float4 screenPos;
            float3 viewDir;
            float3 viewDirTangent;
        };

        half _Glossiness;
        fixed4 _WaterColor, _DeepWaterColor;
        float _FogThreshHold,
            _FoamThreshHold , _FoamLines, _FoamLinesSpeed, _FoamTexSpeed, _FoamIntensity, _FrenselPower,
            _RefractionStrength, _FogDesity, _DistortionSpeed,
            _ParallexRange, _CausticSpeed;

        struct SurfaceOutputWater
        {
            fixed3 Albedo;  
            fixed3 Normal;  
            fixed3 Emission;
            half Specular;  
            fixed Smoothness;
            fixed Alpha;    
        };

        float4 LightingWater(SurfaceOutputWater s,float3 lightDir, float3 viewDir,half atten)
        {
            fixed4 color = fixed4(s.Albedo + s.Emission, s.Alpha);
            float ndotl = saturate(dot(s.Normal, normalize(lightDir)));
            float shadow = ndotl * atten;
            color.rgb *= shadow;

            float3 halfVector = normalize(viewDir + lightDir);
            float specular = pow(max(dot(s.Normal, halfVector), 0), s.Smoothness * 200);

            fixed3 specularColor = _LightColor0.rgb * specular * atten;

            color.rgb += specularColor;

            return color;
        }

        float3 CalculateReflaction(float4 screenPos, float3 tangantNormal)
        {
            float offset = tangantNormal.xy * _RefractionStrength;
            float2 uv = (screenPos.xy + offset) / screenPos.w;
            float3 bgColor = tex2D(_WaterBackground, uv).rgb;

            return bgColor;
        }

        float2 DistortionUV(float2 uv, float speed)
        {
            float2 NewUV = uv + speed * _Time.y;
            return NewUV;
        }

        float3 CalculateNormal(sampler2D normTex,float2 uv)
        {
            float2 uvA = DistortionUV(uv, _DistortionSpeed);
            float2 uvB = DistortionUV(uv, -_DistortionSpeed);

            float3 normalA = UnpackNormal(tex2D(normTex, uvA));
            float3 normalB = UnpackNormal(tex2D(normTex, uvB));

            float3 normal = normalize(normalA + normalB);

            return normal;
        }



        // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
        // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
        // #pragma instancing_options assumeuniformscaling
        UNITY_INSTANCING_BUFFER_START(Props)
            // put more per-instance properties here
        UNITY_INSTANCING_BUFFER_END(Props)

        void surf (Input IN, inout SurfaceOutputWater o)
        {

            //Depth
            float depth = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(IN.screenPos));
            depth = LinearEyeDepth(depth);

            float diff = depth - IN.screenPos.w;
            //MainColor
            float fog = (diff) / _FogThreshHold;
            float4 mainColor = lerp(_WaterColor, _DeepWaterColor, fog); 
            float4 mainTex = tex2D(_MainTex, IN.uv_MainTex);

            mainColor *= mainTex;

            //Foam
            float foamDiff = (diff) / _FoamThreshHold;
            float foamTex = tex2D(_FoamTex, IN.uv_FoamTex + float2(1, 1) * _FoamTexSpeed * _Time.y).r;
            float foam = step(foamDiff - (saturate(sin((foamDiff - _Time.y * _FoamLinesSpeed) * 8 * UNITY_PI * _FoamLines)) * (1.0 - foamDiff)), foamTex);
            

            //Frensel
            float frensel = pow(1 - saturate(dot(o.Normal, normalize(IN.viewDir))),_FrenselPower);

            //refraction
            float3 normal = CalculateNormal(_WaterNormal, IN.uv_WaterNormal);
            float3 bgColor = CalculateReflaction(IN.screenPos, normal);
            o.Normal = normal;

            //caustics
            float3 groundCorrds = ((_WorldSpaceCameraPos - IN.worldPos) / IN.screenPos.w * depth - _WorldSpaceCameraPos)*_ParallexRange ;
            float3 caustics = tex2D(_CausticTex, groundCorrds.xz + _Time.y *_CausticSpeed);

            o.Albedo = mainColor;
            o.Smoothness = _Glossiness;
            o.Emission = foam + lerp((bgColor * fog * -_FogDesity),0, frensel) + (caustics * lerp(1,0,fog));
            o.Alpha = lerp(frensel * mainColor.a, 1, fog);
        }
        ENDCG
    }
    FallBack "Diffuse"
}
