// composite block is a block that is built from a block sequence (as opposed to an HLSL string apply function)
CompositeBlock GeometryShader_ControlBlock_TriangleModifier
{
	[Triangle]
	in Stream inStream;

	[MaxVertexCount(3)]
	[Triangle]
	out Stream outStream;

	CustomizationPoint preTriangleVertexOperations;		// in Stream inStream v, out GeomVert orig);
	CustomizationPoint triangleOperations;				// (inout GeomVert v[3], in GeomVert orig[3]);
	CustomizationPoint postTriangleVertexOperations;	// (inout GeomVert v, in GeomVert orig);

	BlockSequence
	{
		// StreamInstances can only be passed to blocks as in or inout parameters
		// pure out is not allowed (as it breaks our ability to track the data flow)
		// -- effectively we need to treat it as if we are passing them by reference...
		StreamInstance[3] v = inStream;

		// apply per-vertex operations (before triangle operations)
		preTriangleVertexOperations(inout v[0], in inStream[0]);
		preTriangleVertexOperations(inout v[1], in inStream[1]);
		preTriangleVertexOperations(inout v[2], in inStream[2]);

		// apply triangle operations
		triangleOperations(inout v, in inStream);

		// apply per-vertex operations (after triangle operations)
		postTriangleVertexOperations(inout v[0], in inStream[0]);
		postTriangleVertexOperations(inout v[1], in inStream[1]);
		postTriangleVertexOperations(inout v[2], in inStream[2]);

		// write to output stream
		outStream.Emit(v[0]);
		outStream.Emit(v[1]);
		outStream.Emit(v[2]);
	}
}



// Examples of user blocks that could be placed in the customization points
// these blocks can be mixed and matched, to combine effects
// by just swapping the set of blocks bound to each CP

Block UserBlock_PerTriangle_SetNormalsToFlatShaded
{
	// override vertex normals to flat shade the triangle

	inout StreamInstance[3] v
	{
		in float3 positionWS;
		inout float3 normalWS;
		// issue:  if we accidentally declare normalWS as "out" --
		// we might have the situation where there is no error, but it doesn't work as intended...
	}

	[default(1.0f)]
	in float flatShadeAmount;

	void Apply()
	{
		float3 e0 = v[1].positionWS - v[0].positionWS;
		float3 e1 = v[2].positionWS - v[0].positionWS;
		float3 flatNormal = normalize(cross(e0, e1));  // might have this backwards.. depends on triangle cull winding

		// annoying that we have to copy inputs to outputs manually here
		// if we allowed combined input/output state we wouldn't have to...

		// override normals
		v[0].normalWS = lerp(v[0].normalWS, flatNormal, flatShadeAmount);
		v[1].normalWS = lerp(v[1].normalWS, flatNormal, flatShadeAmount);
		v[2].normalWS = lerp(v[2].normalWS, flatNormal, flatShadeAmount);
	}
}


CompositeBlock UserBlock_PerTriangle_ShrinkEraseTriangle
{
	// shrink the rasterized area of each triangle,
	// while keeping interior fragment results constant

	// composite blocks don't need to declare what they read and write from the stream
	// as we can derive that information directly from our parsing of the block sequence
	// (and in this case, the answer is "everything that happens to be there".. i.e. treat it as a 100% passthrough)
	inout StreamInstance v;

	[Property] [default(0.5f)]
	in float shrinkAmount;

	// this is near impossible to express
	BlockSequence
	{
		Blend3<StreamInstance>(v[0], 0.333f, v[1], 0.333f, v[2], 0.334f, out vCenter);
		Lerp<StreamInstance>(v[0], vCenter, shrinkAmount, out v[0]);
		Lerp<StreamInstance>(v[1], vCenter, shrinkAmount, out v[1]);
		Lerp<StreamInstance>(v[2], vCenter, shrinkAmount, out v[2]);
		return outputs;
	}
}


Block UserBlock_PerTriangle_ExplodeMeshTriangles
{
	// split the mesh into separate triangles and make them fly apart like in an explosion
	// applying an initial velocity, gravity and a rotation to each triangle independently

	inout StreamInstance[3] v
	{
		inout float3 positionWS;
		inout float3 normalWS;
		inout float3 tangentWS;
		inout float3 bitangentWS;
	}

	[Property] [default(float3(0.0f,0.0f,0.0f))]
	in float3 explosionOrigin;
	[Property] [default(1.0f)]
	in float initialVelocityMultiplier;
	[Property] [default(1.0f)]
	in float rotationSpeed;
	[Property] [default(1.0f)]
	in float gravityAcceleration;
	[default(0.0f)]
	in float time;		// time since the explosion occurred (must be hooked up)

	void Apply()
	{
		float3 vCenterPosWS = v[0].positionWS * 0.333f + v[1].positionWS * 0.333f + v[2].positionWS * 0.334f;
		float3 initialVelocity = (vCenterPosWS - explosionOrigin) * initialVelocityMultipler;
		float3 rotationAxis = normalize(cross(initialVelocity, float3(0.0f, 1.0f, 0.0f)));

		// calculate new center position applying velocity and gravity
		float3 newCenterPositionWS = vCenterPosWS + initialVelocity * time + float3(0.0f, -gravityAcceleration, 0.0f) * time * time;
		float3x3 rotationMatrix = MatrixFromAxisAngle(rotationAxis, time * rotationSpeed);

		// rotate points around vCenter by rotation matrix, then offset to new position
		v[0].positionWS = rotationMatrix * (v[0].positionWS - vCenter.positionWS) + newCenterPositionWS;
		v[0].normalWS = rotationMatrix * v[0].normalWS;
		v[0].tangentWS = rotationMatrix * v[0].tangentWS;
		v[0].bitangentWS = rotationMatrix * v[0].bitangentWS;

		v[1].positionWS = rotationMatrix * (v[1].positionWS - vCenter.positionWS) + newCenterPositionWS;
		v[1].normalWS = rotationMatrix * v[1].normalWS;
		v[1].tangentWS = rotationMatrix * v[1].tangentWS;
		v[1].bitangentWS = rotationMatrix * v[1].bitangentWS;

		v[2].positionWS = rotationMatrix * (v[2].positionWS - vCenter.positionWS) + newCenterPositionWS;
		v[2].normalWS = rotationMatrix * v[2].normalWS;
		v[2].tangentWS = rotationMatrix * v[2].tangentWS;
		v[2].bitangentWS = rotationMatrix * v[2].bitangentWS;
	}
}


Block UserBlock_PerVertex_OffsetPositionAlongNormal
{
	in StreamInstance v
	{
		inout float3 positionWS;
		in float3 normalWS;
	}

	[Property]
	in float offsetAmount;

	Outputs Apply(Inputs inputs)
	{
		v.positionWS += v.normalWS * offsetAmount;
	}
}

