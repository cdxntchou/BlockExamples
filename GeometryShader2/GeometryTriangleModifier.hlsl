
GeometryStage GeometryShader_ControlBlock_TriangleModifier
{
	// the GeometryStage linker is looking for these input and output streams
	// to define the I/O of the geometry shader
	[Triangle]
	in Stream inStream;

	[MaxVertexCount(3)]
	[Triangle]
	out Stream outStream;

	// StreamInstances (name TBD) are a group of related values -- in this case, each StreamInstance
	// contains all values pertaining to a vertex in the input or output stream.

	// StreamInstances allow blocks to add values to them; they are not a fixed struct,
	// but rather a representation of the grouping of a set of values that can be passed around
	// as a group.

	CustomizationPoint preTriangleVertexOperations
	{
		inout StreamInstance v;
	}
	CustomizationPoint triangleOperations
	{
		inout StreamInstance v0;
		inout StreamInstance v1;
		inout StreamInstance v2;
	}
	CustomizationPoint postTriangleVertexOperations
	{
		inout StreamInstance v;
	}

	BlockGraph
	{
		// copy assignments
		v0 = inStream[0];
		v1 = inStream[1];
		v2 = inStream[2];

		// apply per-vertex operations (before triangle operations)
		preTriangleVertexOperations(v0);		// positional param matching syntax (would be nice)
		preTriangleVertexOperations(v1);
		preTriangleVertexOperations(v2);

		// apply triangle operations
		triangleOperations;

		// apply per-vertex operations (after triangle operations)
		postTriangleVertexOperations(v: v0);	// named parameter matching
		postTriangleVertexOperations(v: v1);
		postTriangleVertexOperations(v: v2);

		// write to output stream (must be done in a block sequence)
		outStream.Emit(v0);
		outStream.Emit(v1);
		outStream.Emit(v2);
	}
}



// Examples of user blocks that could be placed in the customization points
// these blocks can be mixed and matched, to combine effects
// by just swapping the set of blocks bound to each CP

Block UserBlock_PerTriangle_SetNormalsToFlatShaded
{
	// override vertex normals to flat shade the triangle

	// inside HLSL-backed blocks, StreamInstances are represented as a locally-defined struct type
	// the struct will contain at minimum the declared members, which are mapped to StreamInstance data if possible.

	// there may be additional members of the struct (for other members of the StreamInstance), but their names are obfuscated.
	// they are only present to enable passthrough of instance related data and generic blending operations.
	typedef StreamInstance LocalVertex	// StreamInstance declaration syntax TBD
	{
		// in and out declarations help us populate the StreamInstance when linking
		in float3 positionWS;		// in makes a value live upstream (and issues an error if no value or default is provided)
		out float3 normalWS;		// out adds the value, or marks it as dead upstream if it is already there
	};

	// use of a StreamInstance type means this block can not concretized until we resolve
	// the active StreamInstance members, as the concrete local type must be generated to match them
	inout LocalVertex v0, v1, v2;

	void Apply()
	{
		float3 e0 = v1.positionWS - v0.positionWS;
		float3 e1 = v2.positionWS - v0.positionWS;
		float3 flatNormal = normalize(cross(e0, e1));  // might have this backwards.. depends on triangle cull winding

		v0.normalWS = flatNormal;
		v1.normalWS = flatNormal;
		v2.normalWS = flatNormal;
	}
}


Block UserBlock_PerTriangle_ShrinkEraseTriangle
{
	// shrink the rasterized area of each triangle,
	// while keeping interior fragment results constant

	typedef StreamInstance LocalVertex
	{
		// in this case, this block doesn't actually need to know about ANY of the members of the type
		// as we only use generic struct operations
	};

	inout LocalVertex v0, v1, v2;

	[Property] [default(0.5f)]
	in float shrinkAmount;

	void Apply()
	{
		LocalVertex vCenter = Blend3<LocalVertex>(v0, 0.333f, v1, 0.333f, v2, 0.334f);
		v0 = Lerp<LocalVertex>(v0, vCenter, shrinkAmount);
		v1 = Lerp<LocalVertex>(v1, vCenter, shrinkAmount);
		v2 = Lerp<LocalVertex>(v2, vCenter, shrinkAmount);
	}
}


Block UserBlock_PerTriangle_ExplodeMeshTriangles
{
	// split the mesh into separate triangles and make them fly apart like in an explosion
	// applying an initial velocity, gravity and a rotation to each triangle independently

	typedef StreamInstance LocalVertex
	{
		inout float3 positionWS;
		inout float3 normalWS;
		inout float3 tangentWS;
		inout float3 bitangentWS;
	};

	inout LocalVertex v0, v1, v2;

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
		float3 vCenterPosWS = v0.positionWS * 0.333f + v1.positionWS * 0.333f + v2.positionWS * 0.334f;
		float3 initialVelocity = (vCenterPosWS - explosionOrigin) * initialVelocityMultipler;
		float3 rotationAxis = normalize(cross(initialVelocity, float3(0.0f, 1.0f, 0.0f)));

		// calculate new center position applying velocity and gravity
		float3 newCenterPositionWS = vCenterPosWS + initialVelocity * time + float3(0.0f, -gravityAcceleration, 0.0f) * time * time;
		float3x3 rotationMatrix = MatrixFromAxisAngle(rotationAxis, time * rotationSpeed);

		// rotate points around vCenter by rotation matrix, then offset to new position
		v0.positionWS = rotationMatrix * (v0.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v0.normalWS = rotationMatrix * v0.normalWS;
		v0.tangentWS = rotationMatrix * v0.tangentWS;
		v0.bitangentWS = rotationMatrix * v0.bitangentWS;

		v1.positionWS = rotationMatrix * (v1.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v1.normalWS = rotationMatrix * v1.normalWS;
		v1.tangentWS = rotationMatrix * v1.tangentWS;
		v1.bitangentWS = rotationMatrix * v1.bitangentWS;

		v2.positionWS = rotationMatrix * (v2.positionWS - vCenter.positionWS) + newCenterPositionWS;
		v2.normalWS = rotationMatrix * v2.normalWS;
		v2.tangentWS = rotationMatrix * v2.tangentWS;
		v2.bitangentWS = rotationMatrix * v2.bitangentWS;
	}
}


Block UserBlock_PerVertex_OffsetPositionAlongNormal
{
	typedef StreamInstance LocalVertex
	{
		inout float3 positionWS;
		in float3 normalWS;
	};

	inout LocalVertex v;

	[Property]
	[default(1.0f)]
	in float offsetAmount;

	Outputs Apply(Inputs inputs)
	{
		v.positionWS += v.normalWS * offsetAmount;
	}
}

