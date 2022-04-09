
// this is an example of potential hull and domain declarations implementing the current HDRP tessellation
// making use of partial structs to represent stream instances


[maxtessfactor(MAX_TESSELLATION_FACTORS)]	// this uses a #define in HDRP -- not sure if we can support that well?
[domain("tri")]								// tri, quad or isoline
[partitioning("fractional_odd")]			// integer, fractional_even, fractional_odd, or pow2
[outputtopology("triangle_cw")]				// point, line, triangle_cw, or triangle_ccw
[outputcontrolpoints(3)]					// number of output control points (GenerateControlPoint gets called once per point)
HullStage TessellationHull
{
	// The hull stage has TWO independent entry points, so we need some way to specify both.
	// Here I've declared two blocks that could be translated into the entry points.
	// Whether they are bound by name, metadata, or some other means is TBD
	Block GenerateControlPoint
	{
		partial struct HullPoint;

		// inPoints gets read from InputPatch<V2H,3> in the generated shader (linker generated code does conversion)
		// it is a stream of vertex stage outputs
		// since we are using a triangle domain, we get 3 input vertices on each invocation
		in HullPoint[3] inPoints;
		// in InputStream<HullPoint> inPoints;	// alternative representation with a wrapper that could read directly from InputPatch

		[SV_PrimitiveID]
		in uint primitiveID;

		[SV_OutputControlPointID]
		in uint id;

		// this gets converted to H2D_ControlPoint in the generated shader (linker generated code does conversion)
		out HullPoint outControlPoint;

		void Apply()
		{
			// pass through all data!
			outControlPoint = inPoints[id];
		}
	}

	Block GeneratePatchConstantData
	{
		partial struct HullPoint
		{
			in float3 positionRWS;
			in float3 normalWS;
			in float tessellationFactor;
		};

		// inPoints gets read from InputPatch<V2H,3> in the generated shader (linker generated code does conversion)
		in HullPoint[3] inPoints;

		[SV_PrimitiveID]
		in uint primitiveID;

		// any output of the GeneratePatchConstantData block are placed in "H2D_ConstantData" in the generated shader, and passed as input to domain shader
		// any data flagged SV_TessFactor or SV_InsideTessFactor are additionally sent to the hardware tessellator to generate domain locations
		[SV_TessFactor]
		out float edgeTess[3];	// [4] when using [domain("quad"]

		[SV_InsideTessFactor]
		out float insideTess;	// [2] when using [domain("quad"]

		// here we can specify have any additional outputs we want to pass to the domain shader.  None needed for HDRP implementation

		void Apply()
		{
			// x - 1->2 edge
			// y - 2->0 edge
			// z - 0->1 edge
			// w - inside tessellation factor (calculate as mean of three in GetTessellationFactors())
			float3 inputTessellationFactors;
			inputTessellationFactors.x = 0.5 * (inPoints[1].tessellationFactor + inPoints[2].tessellationFactor);
			inputTessellationFactors.y = 0.5 * (inPoints[2].tessellationFactor + inPoints[0].tessellationFactor);
			inputTessellationFactors.z = 0.5 * (inPoints[0].tessellationFactor + inPoints[1].tessellationFactor);

			// plain function in HDRP include, left out for brevity
			float4 tf = GetTessellationFactors(
				inPoints[0].positionRWS, inPoints[1].positionRWS, inPoints[2].positionRWS,
				inPoints[0].normalWS, inPoints[1].normalWS, inPoints[2].normalWS,
				inputTessellationFactors);

			// output tessellation factors
			edgeTess[0] = min(tf.x, MAX_TESSELLATION_FACTORS);
			edgeTess[1] = min(tf.y, MAX_TESSELLATION_FACTORS);
			edgeTess[2] = min(tf.z, MAX_TESSELLATION_FACTORS);
			insideTess = min(tf.w, MAX_TESSELLATION_FACTORS);
		}
	}
}


[domain("tri")] // this must use the same domain as the HullStage
DomainStage TessellationDomain
{
	partial struct DomainPoint;

	// HDRP provides a post-tessellation callback to implement things like vertex animation.
	// the thought here:  [LinkStructFields] basically means : link CP inputs and outputs to fields of the DomainPoint struct
	// this way the customization point interface doesn't care about DomainPoint struct, and can deal directly in each individual field
	// useful in cases where the CP is inherently only dealing with a single instance

	CustomizationPoint PostTessellationVertexModification([LinkStructFields] inout DomainPoint p, in float3 timeParams);

	// input: control points from the hull stage
	in DomainPoint[3] inPoints
	{
		in float3 positionRWS;
		in float3 normalWS; // only when phong enabled
	};

	// input: patch constants from hull stage
	[SV_TessFactor]
	in float edgeTess[3];

	[SV_InsideTessFactor]
	in float insideTess;

	// input: tessellation factors
	[SV_DomainLocation]
	in float3 baryCoords; // float3 barycentrics for a triangle domain, float2 UV for a quad domain

	[Keyword]	// keyword by default if unbound... ?  controlled by an HDRP target setting at the moment...
	in bool phongTessellationEnabled;

	out DomainPoint result
	{
		out float3 positionRWS;		// only when phong enabled
		out float3 positionPredisplacementRWS;
	}

	void Apply()
	{
		result = Blend3<DomainVert>(inPoints[0], baryCoords.x, inPoints[1], baryCoords.y, inPoints[2], baryCoords.z);

		if (phongTessellationEnabled)
		{
			result.positionRWS = PhongTessellation(
				result.positionRWS,
				inPoints[0].positionRWS, inPoints[1].positionRWS, inPoints[2].positionRWS,
				inPoints[0].normalWS, inPoints[1].normalWS, inPoints[2].normalWS,
				baryCoords, _TessellationShapeFactor);
		}

		// can always generate this -- if it's not requested downstream, we automatically don't interpolate it and it is compiled out
		result.positionPredisplacementRWS = result.positionRWS;

		// just in case tessellation modification reads positionCS, we set it up here.
		// (if unused this will compile out)
		result.positionCS = TransformWorldToHClip(result.positionRWS);

		// HDRP provides a post-tessellation callback to implement things like vertex animation
		PostTessellationVertexModification(result, _TimeParameters.xyz);

		// then we set it again here to account for any vertex position changes that occurred
		result.positionCS = TransformWorldToHClip(result.positionRWS);
	}
}
