Block GeometryShader_ControlBlock_TriangleModifier
{
	// this block is intended to be used as the top level control block for a geometry shader that wants to modify triangles
	// it makes use of customization points to do the actual modification on a per-vertex or per-triangle basis

	// this declares a global partial structure
	// global meaning it is a shared by all blocks that declare the same name
	// partial meaning that each block only needs to declare the fields that it interacts with
	// the actual final structure will be a superset of all block declared fields
	// (and may also include additional fields added by linking for passthrough, when the type is used as a stream type)
	global partial struct GeomVert
	{
		in float3 positionWS;
		out float4 positionCS;
	}

	Inputs
	{
		// InputStream<T> is a generated type that wraps an input stream, and can read data from the stream into the specified structure
		[Triangle] InputStream<GeomVert> inStream;

		// OutputStream<T> is a generated type similar to InputStream, but can write data to the stream from the specified structure
		// it's not clear what the best way to specify MaxVertexCount is, but this is one option
		// THOUGHT: it is somewhat weird that outStream needs to be declared in the INPUTS, but that's how it works...
		// the actual output occurs as a side effect of calling the Write/Emit function on this stream.
		[MaxVertexCount(3)][Triangle] OutputStream<GeomVert> outStream;

		// this example is making use of Josh's proposal for invoking customization points from within blocks
		CustomizationPoint preTriangleVertexOperations(inout GeomVert v, in GeomVert orig);
		CustomizationPoint triangleOperations(inout GeomVert v[3], in GeomVert orig[3]);
		CustomizationPoint postTriangleVertexOperations(inout GeomVert v, in GeomVert orig);
		// CustomizationPoint generateMoreTrianglesCP(inout GeomVert v[3], in GeomVert orig[3], in OutputStream<GeomVert> outStream);
	}

	Outputs
	{
	}

	Outputs Apply(Inputs inputs)
	{
		// make use of the InputStream<> generated Read() function to read the input vertices from the input stream
		GeomVert v[3];
		v[0] = inputs.inStream.Read(0);
		v[1] = inputs.inStream.Read(1);
		v[2] = inputs.inStream.Read(2);

		// make a copy of the original data, in case any customization point cares
		GeomVert orig[3];
		orig[0] = v[0]; orig[1] = v[1]; orig[2] = v[2];

		// apply per-vertex operations (before triangle operations)
		for (int i = 0; i < 3; i++)
		{
			preTriangleVertexOperations(v[i], orig[i]);
		}

		// apply triangle operations
		triangleOperations(v, orig);

		// apply per-vertex operations (after triangle operations)
		for (int i = 0; i < 3; i++)
		{
			postTriangleVertexOperations(v[i], orig[i]);
		}

		// ensure positionCS is transformed correctly from positionWS
		v[0].positionCS = TransformPoint(v[0].positionWS);
		v[1].positionCS = TransformPoint(v[1].positionWS);
		v[2].positionCS = TransformPoint(v[2].positionWS);

		// emit output triangle (via OutputStream<> generated Write() function)
		inputs.outStream.Write(v[0]);
		inputs.outStream.Write(v[1]);
		inputs.outStream.Write(v[2]);
		inputs.outStream.RestartStrip();

		// we could, for example, pass the OutputStream to the "generateMoreTrianglesCP"
		// to enable user code to generate additional triangles if they wanted...
		// we would need to somehow figure out how to update the MaxVertexCount appropriately.
		// generateMoreTrianglesCP.Execute(v, orig, outputs.outStream);

		// so this return is actually returning nothing...
		Outputs outputs;
		return outputs;
	}
}

// Examples of user blocks that could be placed in the customization points
// these blocks can be mixed and matched, to combine effects
// by just swapping the set of blocks bound to each CP

Block UserBlock_PerTriangle_SetNormalsToFlatShaded
{
	// override vertex normals to flat shade the triangle

	global partial struct GeomVert
	{
		in float3 positionWS;
		inout float3 normal;
	}

	Inputs
	{
		GeomVert v[3];
		[default(1.0f)] float flatShadeAmount;
	}

	Outputs
	{
		GeomVert v[3];
	}

	Outputs Apply(Inputs inputs)
	{
		float3 e0 = inputs.v[1].positionWS - inputs.v[0].positionWS;
		float3 e1 = inputs.v[2].positionWS - inputs.v[0].positionWS;
		float3 flatNormal = normalize(cross(e0, e1));  // might have this backwards.. depends on triangle cull winding

		// annoying that we have to copy inputs to outputs manually here
		// if we allowed combined input/output state we wouldn't have to...
		Outputs outputs;
		outputs.v[0] = inputs.v[0];
		outputs.v[1] = inputs.v[1];
		outputs.v[2] = inputs.v[2];

		// override normals
		outputs.v[0].normal = lerp(inputs.v[0].normal, flatNormal, flatShadeAmount);
		outputs.v[1].normal = lerp(inputs.v[1].normal, flatNormal, flatShadeAmount);
		outputs.v[2].normal = lerp(inputs.v[2].normal, flatNormal, flatShadeAmount);

		return outputs;
	}
}


Block UserBlock_PerTriangle_ShrinkEraseTriangle
{
	// shrink the rasterized area of each triangle,
	// while keeping interior fragment results constant

	global partial struct GeomVert
	{
	}

	Inputs
	{
		GeomVert v[3];
		[Property] [default(0.5f)] float shrinkAmount;
	}

	Outputs
	{
		GeomVert v[3];
	}

	Outputs Apply(Inputs inputs)
	{
		// Blend3 and Lerp need to be generated functions, even more so when used on generated types
		// (another use case for generic support..)
		GeomVert vCenter = Blend3<GeomVert>(inputs.v[0], 0.333f, inputs.v[1], 0.333f, inputs.v[2], 0.334f);

		Outputs outputs;
		outputs.v[0] = Lerp<GeomVert>(inputs.v[0], vCenter, shrinkAmount);
		outputs.v[1] = Lerp<GeomVert>(inputs.v[1], vCenter, shrinkAmount);
		outputs.v[2] = Lerp<GeomVert>(inputs.v[2], vCenter, shrinkAmount);
		return outputs;
	}
}


Block UserBlock_PerTriangle_ExplodeMeshTriangles
{
	// split the mesh into separate triangles and make them fly apart like in an explosion
	// applying an initial velocity, gravity and a rotation to each triangle independently

	global partial struct GeomVert
	{
		inout float3 positionWS;
		inout float3 normalWS;
		inout float3 tangentWS;
		inout float3 bitangentWS;
	}

	Inputs
	{
		GeomVert v[3];
		[Property] [default(float3(0.0f,0.0f,0.0f))] float3 explosionOrigin;
		[Property] [default(1.0f)] float initialVelocityMultiplier;
		[Property] [default(1.0f)] float rotationSpeed;
		[Property] [default(1.0f)] float gravityAcceleration;
		[default(0.0f)] float time;		// time since the explosion occurred (must be hooked up)
	}

	Outputs
	{
		GeomVert v[3];
	}

	Outputs Apply(Inputs inputs)
	{
		GeomVert v0 = inputs.v[0];
		GeomVert v1 = inputs.v[1];
		GeomVert v2 = inputs.v[2];
		GeomVert vCenter = Blend3<GeomVert>(v0, 0.333f, v1, 0.333f, v2, 0.334f);

		float3 initialVelocity = (vCenter.positionWS - explosionOrigin) * initialVelocityMultipler;
		float3 rotationAxis = normalize(cross(initialVelocity, float3(0.0f, 1.0f, 0.0f)));

		// calculate new center position applying velocity and gravity
		float3 newCenterPositionWS = vCenter.positionWS + initialVelocity * time + float3(0.0f, -gravityAcceleration, 0.0f) * time * time;
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

		Outputs outputs;
		outputs.v[0] = v0;
		outputs.v[1] = v1;
		outputs.v[2] = v2;
		return outputs;
	}
}


Block UserBlock_PerVertex_OffsetPositionAlongNormal
{
	global partial struct GeomVert
	{
		inout float3 positionWS;
		in float3 normalWS;
	}

	Inputs
	{
		GeomVert v;
		[Property] float offsetAmount;
	}

	Outputs
	{
		GeomVert v;
	}

	Outputs Apply(Inputs inputs)
	{
		// annoying that we have to copy inputs to outputs manually here
		// if we allowed combined input/output state we wouldn't have to...
		Outputs outputs;
		outputs.v = inputs.v;

		outputs.v.positionWS = inputs.v.positionWS + inputs.v.normalWS * inputs.offsetAmount;
		return outputs;
	}
}

