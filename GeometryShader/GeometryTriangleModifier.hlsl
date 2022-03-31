Block GeometryShader_ControlBlock_TriangleModifier
{
	// this block is intended to be used as the top level control block for a geometry shader that wants to modify triangles
	// it makes use of customization points to do the actual modification on a per-vertex or per-triangle basis

	// this declares a global partial structure
	// global meaning it is a shared by all blocks that declare the same name
	// partial meaning that each block only needs to declare the fields that it interacts with
	// the actual final structure will be a superset of all block declared fields
	// (and may also include additional fields added by linking for passthrough, when the type is used as a stream)
	global partial struct GeomVert
	{
		// in this case the control block doesn't directly access any vertex data,
		// so no need to declare any fields here
	}

	Inputs
	{
		[Triangle] InputStream<GeomVert> inStream;
		CustomizationPoint preVertexCP(inout GeomVert v, in GeomVert orig);
		CustomizationPoint triangleCP(inout GeomVert v[3], in GeomVert orig[3]);
		CustomizationPoint postVertexCP(inout GeomVert v, in GeomVert orig);
		// CustomizationPoint generateMoreTrianglesCP(inout GeomVert v[3], in GeomVert orig[3], in OutputStream<GeomVert> outStream);
	}

	Outputs
	{
		[MaxVertexCount(3)] [Triangle] OutputStream<GeomVert> outStream;
	}

	Outputs Apply(Inputs inputs)
	{
		GeomVert v[3];
		v[0] = inputs.inStream.Read(0);
		v[1] = inputs.inStream.Read(1);
		v[2] = inputs.inStream.Read(2);

		GeomVert orig[3];
		orig[0] = v[0]; orig[1] = v[1]; orig[2] = v[2];

		// apply per-vertex operations (pre-triangle operations)
		for (int i = 0; i < 3; i++)
		{
			preVertexCP.Execute(v[i], orig[i]);
		}

		// apply triangle operations
		triangleCP.Execute(v, orig);

		// apply per-vertex operations (post-triangle operations)
		for (int i = 0; i < 3; i++)
		{
			postVertexCP.Execute(v[i], orig[i]);
		}

		// write output triangle
		Outputs outputs;

		// somewhat weird that outStream is in the output structure...
		// when in reality, the outStream is actually an INPUT to the function,
		// and the actual output occurs as a side effect of calling Write()
		outputs.outStream.Write(v[0]);
		outputs.outStream.Write(v[1]);
		outputs.outStream.Write(v[2]);

		// we could, for example, pass the output stream to the "generateMoreTrianglesCP"
		// to enable user code to generate additional triangles if they wanted...
		// we would need to somehow figure out how to update the MaxVertexCount appropriately.
		// generateMoreTrianglesCP.Execute(v, orig, outputs.outStream);

		// so this return is actually returning nothing...
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
		in float3 position;
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
		float3 e0 = inputs.v[1].position - inputs.v[0].position;
		float3 e1 = inputs.v[2].position - inputs.v[0].position;
		float3 flatNormal = normalize(cross(e0, e1));  // might have this backwards... todo

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
	// shrink the rasterized area of each triangle, while keeping interior fragment results constant
	global partial struct GeomVert
	{
		inout float3 position;
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
		// Blend needs to be a generated function for deferred structs like GeomVert
		GeomVert vCenter = Blend3<GeomVert>(v[0], 0.33f, v[1], 0.33f, v[2], 0.34f);

		Outputs outputs;
		outputs.v[0] = Lerp<GeomVert>(inputs.v[0], vCenter, shrinkAmount);
		outputs.v[1] = Lerp<GeomVert>(inputs.v[1], vCenter, shrinkAmount);
		outputs.v[2] = Lerp<GeomVert>(inputs.v[2], vCenter, shrinkAmount);
		return outputs;
	}
}


Block UserBlock_PerVertex_OffsetPositionAlongNormal
{
	global partial struct GeomVert
	{
		inout float3 position;
		in float3 normal;
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

		outputs.v.position = inputs.v.position + inputs.v.normal * inputs.offsetAmount;
		return outputs;
	}
}

