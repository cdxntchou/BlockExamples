
DomainStage TessellationDomain
{
	Settings
	{
		layout "tri";
	}

	// HDRP provides a post-tessellation callback to implement things like vertex animation.
	// the thought here:  [LinkStructFields] basically means : link CP inputs and outputs to fields of the DomainPoint struct
	// this way the customization point interface doesn't care about DomainPoint struct, and can deal directly in each individual field
	// useful in cases where the CP is inherently only dealing with a single instance

	CustomizationPoint PostTessellationVertexModification
	{
		inout Group vertex
		{
			// only these template values are available to the user blocks in the customization point
			inout float3 positionRWS;
			inout float3 normalWS;
			inout float3 tangentWS;
			inout float3 uv0;
			// the user blocks can add additional values to this group, but only in user namespace
		};
		in float3 timeParams;
	}

	// input: control point data from the hull stage
	in float3[3] positionRWS;
	in float3[3] normalWS;

	// there implicitly exists additional passthrough data here from the control points, in similar arrays
	in Group[3] extraData;	// maybe we make it explicit?

	// input: patch constants from hull stage
	[SV_TessFactor]
	in float edgeTess[3];

	[SV_InsideTessFactor]
	in float insideTess;

	// input: domain location from hardware tessellator
	[SV_DomainLocation]
	in float3 baryCoords; // float3 barycentrics for a triangle domain, float2 UV for a quad domain

	[Keyword]	// keyword by default if unbound... ?  controlled by an HDRP target setting at the moment...
	in bool phongTessellationEnabled;

	out Group outVertex;

	BlockSequence
	{
		// generated function provides group of outputs, that are the result of blending any array[3] data present as inputs
		outVertex = MapBlend3(baryCoords);

		[if(phongTessellationEnabled)]
		ApplyPhongTessellation(
				inout outVertex.positionRWS, baryCoords,
				positionRWS[0], positionRWS[1], positionRWS[2],
				normalWS[0], normalWS[1], normalWS[2]);

		// generate new group member by copying existing one
		outVertex.positionPredisplacementRWS = outVertex.positionRWS;

		// update group member
		outVertex.positionCS = TransformWorldToHClip(outVertex.positionRWS);

		// pass group to customization point
		PostTessellationVertexModification(outVertex, _TimeParameters.xyz);

		// then we set it again here to account for any vertex position changes that occurred
		outVertex.positionCS = TransformWorldToHClip(outVertex.positionRWS);
	}
}