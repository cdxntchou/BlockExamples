// GS shrink ease + user data

//------------
//- Template -
//------------


VertexStage 
{
	Setup 
	{
		[Position] float4 positionOS;
		[Texcoord0] float2 uv;
	}

	TransformOSToWS;
}


GeometryStage 
{
	Setup
	{
		MaxVertexCount 3
		InputLayout Triangle
		OutputLayout Triangle
	}


	CustomizationPoint EmitSingleVertexCP
	{
		Interface
		{
			in uint vertexIndex;
			// no outputs -- can only generate user-scope data
		}
	}

	BlockSequence GenerateOutputVertex
	{
		in float vertexIndex;
		in float3[3] v_positionWS;
		in float2[3] v_uv;

		[SystemValue(Position)]
		out float3 positionCS;
		out float2 uv;

		ShrinkEaseTriangle(vertexIndex)->(weights);

		MapBlend3(weights);		// implicitly operating on ALL defined vertex data?   somewhat weird...

		positionCS = TransformWSToCS(positionWS);
		uv = v_uv[vertexIndex];
		EmitSingleVertexCP();
	}

	CustomizationPoint VertexBlendUserOverride
	{
		in int vertexIndex;
		in float3 weights;
	}
	
	BlockSequence PerVertex
	{
		in int vertexIndex;
		inout float3[3] positionWS;
		inout float2[3] uv;
		local float3 weights;


		// interpolate the template level values
		positionWS[vertexIndex] = Blend3(positionWS, weights);
		uv[vertexIndex] = Blend3(uv, weights);
		vertexColor[vertexIndex] = Blend3(vertexColor, weights);

		// invoke blend for user code
		VertexBlendUserOverride(vertexIndex, weights);
	}

	EntryPoint	// block sequence
	{
		// input stream is reorganized into independent arrays per value:  i.e.   float3[3] positionWS;
		Emit<GenerateOutputVertex>(0 : vertexIndex);
		Emit<GenerateOutputVertex>(1 : vertexIndex);
		Emit<GenerateOutputVertex>(2 : vertexIndex);
	}
}


FragmentStage {

	Setup {
		[Color0] half4 color;
	}

	SampleMainTexture2D; // Gets uv from VS, outputs color to the framebuffer. Textures are half4 by default.
	CustomizationPoint FinalColor {
		Interface {
			inout half4 color;
		}
	}(); // Call in place
}

//---------------
//- User shader -
//---------------

Block ShrinkEaseTriangle 
{
	[Property(default = 0.5)] in float shrinkAmount;
	in int vertexIndex;
	out float3 weights;

	void Apply(Interface io) 
	{
		float s = shrinkAmount;
		float x = vertexIndex == 0 ? (1.0 - 0.667 * s) : 0.333 * s;
		float y = vertexIndex == 1 ? (1.0 - 0.667 * s) : 0.333 * s;
		float z = vertexIndex == 2 ? (1.0 - 0.666 * s) : 0.334 * s;
		weights = float3(x, y z);
	}
}

VertexSetup {
	[Texcoord2] half4 vertexColor;
	[Texcoord1] float2 lightmapUV;
}

Blocks {
	Block SampleLightmap {
		...
	}
}

Implementation PerVertex {
	// shrink-blend vertexColor, but leave lightmapUV intact - we don't want to touch it
	Blend3(vertexColor: values)->(value: vertexColor[vertexIndex]);
}

Implementation EmitSingleVertex {
	Passthrough(vertexColor[vertexIndex]: value)->(value: vertexColor);
	Passthrough(lightmapUV[vertexIndex]: value)->(value: lightmapUV);
}

Implementation FinalColor {
	SampleLightmap()->(color.rgb: lightmap);
	Multiply(color.rgb: lhs, lightmap.rgb: rhs)->(value: color.rgb);
	Multiply(color: lhs, vertexColor: rhs)->(value: color);
}
